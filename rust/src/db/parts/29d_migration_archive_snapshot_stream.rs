const VAULT_ROLLBACK_STREAM_MAGIC: &[u8; 8] = b"SLVRB2\0\0";
const VAULT_ROLLBACK_STREAM_CHUNK_SIZE: usize = 1024 * 1024;
const VAULT_ROLLBACK_STREAM_FINAL_FLAG: u8 = 1;

fn vault_rollback_stream_frame_aad(
    chunk_index: u64,
    plaintext_len: usize,
    is_final: bool,
) -> Vec<u8> {
    let mut aad = Vec::with_capacity(VAULT_ROLLBACK_SNAPSHOT_AAD.len() + 32);
    aad.extend_from_slice(VAULT_ROLLBACK_SNAPSHOT_AAD);
    aad.extend_from_slice(b":chunked-v2:");
    aad.extend_from_slice(&chunk_index.to_le_bytes());
    aad.extend_from_slice(&(plaintext_len as u64).to_le_bytes());
    aad.push(if is_final {
        VAULT_ROLLBACK_STREAM_FINAL_FLAG
    } else {
        0
    });
    aad
}

fn vault_rollback_write_encrypted_stream_frame<W: std::io::Write>(
    writer: &mut W,
    cipher: &chacha20poly1305::XChaCha20Poly1305,
    chunk_index: u64,
    plaintext: &[u8],
    is_final: bool,
) -> Result<()> {
    use chacha20poly1305::aead::{Aead, Payload};

    if plaintext.len() > u32::MAX as usize {
        return Err(anyhow!("rollback snapshot chunk is too large"));
    }
    let mut nonce_bytes = [0u8; 24];
    crate::crypto::fill_random_bytes(&mut nonce_bytes)?;
    let aad = vault_rollback_stream_frame_aad(chunk_index, plaintext.len(), is_final);
    let ciphertext = cipher
        .encrypt(
            chacha20poly1305::XNonce::from_slice(&nonce_bytes),
            Payload {
                msg: plaintext,
                aad: &aad,
            },
        )
        .map_err(|_| anyhow!("rollback snapshot stream encrypt failed"))?;
    if ciphertext.len() > u32::MAX as usize {
        return Err(anyhow!("rollback snapshot ciphertext chunk is too large"));
    }

    writer.write_all(&[if is_final {
        VAULT_ROLLBACK_STREAM_FINAL_FLAG
    } else {
        0
    }])?;
    writer.write_all(&(plaintext.len() as u32).to_le_bytes())?;
    writer.write_all(&(ciphertext.len() as u32).to_le_bytes())?;
    writer.write_all(&nonce_bytes)?;
    writer.write_all(&ciphertext)?;
    Ok(())
}

fn vault_rollback_encrypt_zip_file_to_snapshot(
    key: &[u8; 32],
    zip_path: &Path,
    snapshot_path: &Path,
) -> Result<()> {
    use chacha20poly1305::KeyInit;
    use std::io::{Read as _, Write as _};

    if let Some(parent) = snapshot_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temp_path = snapshot_path.with_extension(format!("tmp-{}", uuid::Uuid::new_v4()));
    let encrypt_result = (|| -> Result<()> {
        let cipher = chacha20poly1305::XChaCha20Poly1305::new_from_slice(key)
            .map_err(|_| anyhow!("invalid key"))?;
        let mut input = fs::File::open(zip_path)?;
        let mut output = fs::File::create(&temp_path)?;
        output.write_all(VAULT_ROLLBACK_STREAM_MAGIC)?;
        output.write_all(&(VAULT_ROLLBACK_STREAM_CHUNK_SIZE as u32).to_le_bytes())?;

        let mut buffer = vec![0u8; VAULT_ROLLBACK_STREAM_CHUNK_SIZE];
        let mut chunk_index = 0u64;
        loop {
            let read = input.read(&mut buffer)?;
            if read == 0 {
                break;
            }
            vault_rollback_write_encrypted_stream_frame(
                &mut output,
                &cipher,
                chunk_index,
                &buffer[..read],
                false,
            )?;
            chunk_index += 1;
        }
        vault_rollback_write_encrypted_stream_frame(
            &mut output,
            &cipher,
            chunk_index,
            &[],
            true,
        )?;
        output.flush()?;
        fs::rename(&temp_path, snapshot_path)?;
        Ok(())
    })();

    if encrypt_result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    encrypt_result
}

fn vault_rollback_read_u32<R: std::io::Read>(reader: &mut R, label: &str) -> Result<u32> {
    let mut bytes = [0u8; 4];
    reader
        .read_exact(&mut bytes)
        .map_err(|err| anyhow!("rollback snapshot stream missing {label}: {err}"))?;
    Ok(u32::from_le_bytes(bytes))
}

fn vault_rollback_decrypt_stream_snapshot_to_zip(
    key: &[u8; 32],
    snapshot_path: &Path,
    zip_path: &Path,
) -> Result<()> {
    use chacha20poly1305::aead::{Aead, Payload};
    use chacha20poly1305::KeyInit;
    use std::io::{Read as _, Write as _};

    if let Some(parent) = zip_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let decrypt_result = (|| -> Result<()> {
        let cipher = chacha20poly1305::XChaCha20Poly1305::new_from_slice(key)
            .map_err(|_| anyhow!("invalid key"))?;
        let mut input = fs::File::open(snapshot_path)?;
        let mut magic = [0u8; 8];
        input.read_exact(&mut magic)?;
        if &magic != VAULT_ROLLBACK_STREAM_MAGIC {
            return Err(anyhow!("rollback snapshot stream magic mismatch"));
        }
        let chunk_size = vault_rollback_read_u32(&mut input, "chunk size")? as usize;
        if chunk_size == 0 || chunk_size > VAULT_ROLLBACK_STREAM_CHUNK_SIZE {
            return Err(anyhow!("rollback snapshot stream chunk size is invalid"));
        }

        let mut output = fs::File::create(zip_path)?;
        let mut chunk_index = 0u64;
        loop {
            let mut flag = [0u8; 1];
            match input.read_exact(&mut flag) {
                Ok(()) => {}
                Err(err) if err.kind() == std::io::ErrorKind::UnexpectedEof => {
                    return Err(anyhow!("rollback snapshot stream missing final frame"));
                }
                Err(err) => return Err(err.into()),
            }
            if flag[0] & !VAULT_ROLLBACK_STREAM_FINAL_FLAG != 0 {
                return Err(anyhow!("rollback snapshot stream frame flag is invalid"));
            }
            let is_final = flag[0] & VAULT_ROLLBACK_STREAM_FINAL_FLAG != 0;
            let plaintext_len =
                vault_rollback_read_u32(&mut input, "plaintext chunk length")? as usize;
            let ciphertext_len =
                vault_rollback_read_u32(&mut input, "ciphertext chunk length")? as usize;
            if plaintext_len > chunk_size {
                return Err(anyhow!("rollback snapshot stream plaintext chunk is too large"));
            }
            if ciphertext_len > chunk_size + 16 {
                return Err(anyhow!("rollback snapshot stream ciphertext chunk is too large"));
            }
            if is_final && plaintext_len != 0 {
                return Err(anyhow!(
                    "rollback snapshot stream final frame must have empty plaintext"
                ));
            }
            let mut nonce_bytes = [0u8; 24];
            input
                .read_exact(&mut nonce_bytes)
                .map_err(|err| anyhow!("rollback snapshot stream missing nonce: {err}"))?;
            let mut ciphertext = vec![0u8; ciphertext_len];
            input
                .read_exact(&mut ciphertext)
                .map_err(|err| anyhow!("rollback snapshot stream missing ciphertext: {err}"))?;
            let aad = vault_rollback_stream_frame_aad(chunk_index, plaintext_len, is_final);
            let plaintext = cipher
                .decrypt(
                    chacha20poly1305::XNonce::from_slice(&nonce_bytes),
                    Payload {
                        msg: ciphertext.as_ref(),
                        aad: &aad,
                    },
                )
                .map_err(|_| anyhow!("rollback snapshot stream decrypt failed"))?;
            if plaintext.len() != plaintext_len {
                return Err(anyhow!("rollback snapshot stream plaintext length mismatch"));
            }
            if is_final {
                let mut trailing = [0u8; 1];
                let trailing_len = input.read(&mut trailing)?;
                if trailing_len != 0 {
                    return Err(anyhow!("rollback snapshot stream has trailing data"));
                }
                break;
            }
            output.write_all(&plaintext)?;
            chunk_index += 1;
        }
        output.flush()?;
        Ok(())
    })();

    if decrypt_result.is_err() {
        let _ = fs::remove_file(zip_path);
    }
    decrypt_result
}

fn vault_rollback_snapshot_uses_stream_format(snapshot_path: &Path) -> Result<bool> {
    use std::io::Read as _;

    let mut file = fs::File::open(snapshot_path)?;
    let mut magic = [0u8; 8];
    match file.read_exact(&mut magic) {
        Ok(()) => Ok(&magic == VAULT_ROLLBACK_STREAM_MAGIC),
        Err(err) if err.kind() == std::io::ErrorKind::UnexpectedEof => Ok(false),
        Err(err) => Err(err.into()),
    }
}

fn vault_rollback_extract_zip_archive<R>(app_dir: &Path, reader: R) -> Result<PathBuf>
where
    R: std::io::Read + std::io::Seek,
{
    let stage_dir = migration_archive_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let extract_result = (|| -> Result<()> {
        let mut archive = zip::ZipArchive::new(reader)?;
        for index in 0..archive.len() {
            let mut entry = archive.by_index(index)?;
            let Some(name) = entry.enclosed_name().map(|value| value.to_path_buf()) else {
                continue;
            };
            let out_path = stage_dir.join(name);
            if entry.is_dir() {
                fs::create_dir_all(&out_path)?;
                continue;
            }
            if let Some(parent) = out_path.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut out = fs::File::create(&out_path)?;
            std::io::copy(&mut entry, &mut out)?;
        }
        Ok(())
    })();

    if let Err(err) = extract_result {
        let _ = fs::remove_dir_all(&stage_dir);
        return Err(err);
    }

    Ok(stage_dir)
}

fn vault_rollback_extract_zip_file(app_dir: &Path, zip_path: &Path) -> Result<PathBuf> {
    let file = fs::File::open(zip_path)?;
    vault_rollback_extract_zip_archive(app_dir, file)
}

fn vault_rollback_extract_snapshot_to_stage(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<PathBuf> {
    if vault_rollback_snapshot_uses_stream_format(snapshot_path)? {
        let zip_path = migration_archive_staging_dir(app_dir)
            .join(format!("{}.zip.tmp", uuid::Uuid::new_v4()));
        let extract_result = (|| -> Result<PathBuf> {
            vault_rollback_decrypt_stream_snapshot_to_zip(key, snapshot_path, &zip_path)?;
            vault_rollback_extract_zip_file(app_dir, &zip_path)
        })();
        let _ = fs::remove_file(&zip_path);
        return extract_result;
    }

    let encrypted = fs::read(snapshot_path)?;
    let zip_bytes = decrypt_bytes(key, &encrypted, VAULT_ROLLBACK_SNAPSHOT_AAD)?;
    vault_rollback_extract_zip_bytes(app_dir, &zip_bytes)
}

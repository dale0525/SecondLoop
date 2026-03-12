pub fn download_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    sha256: &str,
) -> Result<()> {
    let app_dir = crate::db::app_dir_from_conn(conn)?;

    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment not found"))?;

    let remote_root_dir = normalize_dir(remote_root);
    let remote_path = format!("{remote_root_dir}attachments/{sha256}.bin");
    let ciphertext = remote.get(&remote_path)?;
    let aad = format!("sync.attachment.bytes:{sha256}");
    let plaintext = decrypt_bytes(sync_key, &ciphertext, aad.as_bytes())?;

    if sha256_hex(&plaintext) != sha256 {
        return Err(anyhow!("attachment sha256 mismatch after download"));
    }

    let local_path = app_dir.join(&stored_path);
    if let Some(parent) = local_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let local_aad = format!("attachment.bytes:{sha256}");
    let local_cipher = encrypt_bytes(db_key, &plaintext, local_aad.as_bytes())?;
    fs::write(local_path, local_cipher)?;
    Ok(())
}

pub fn upload_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    sha256: &str,
) -> Result<bool> {
    let app_dir = crate::db::app_dir_from_conn(conn)?;
    let remote_root_dir = normalize_dir(remote_root);
    let attachments_dir = format!("{remote_root_dir}attachments/");
    remote.mkdir_all(&attachments_dir)?;
    upload_attachment_bytes_if_present(
        conn,
        db_key,
        sync_key,
        remote,
        &attachments_dir,
        app_dir.as_path(),
        sha256,
    )
}

fn upload_all_local_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    attachments_dir: &str,
    app_dir: &Path,
) -> Result<u64> {
    let existing = remote.list(attachments_dir)?;
    let existing: BTreeSet<String> = existing.into_iter().collect();

    let mut stmt =
        conn.prepare(r#"SELECT sha256 FROM attachments ORDER BY created_at ASC, sha256 ASC"#)?;
    let mut rows = stmt.query([])?;

    let mut uploaded = 0u64;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        let remote_path = format!("{attachments_dir}{sha256}.bin");
        if existing.contains(&remote_path) {
            continue;
        }
        match upload_attachment_bytes_if_present(
            conn,
            db_key,
            sync_key,
            remote,
            attachments_dir,
            app_dir,
            &sha256,
        ) {
            Ok(true) => uploaded += 1,
            Ok(false) => {}
            Err(e) => return Err(e),
        }
    }

    Ok(uploaded)
}

fn upload_attachment_bytes_if_present(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    attachments_dir: &str,
    app_dir: &Path,
    sha256: &str,
) -> Result<bool> {
    let exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    if exists.is_none() {
        return Ok(false);
    }

    let plaintext = match crate::db::read_attachment_bytes(conn, db_key, app_dir, sha256) {
        Ok(bytes) => bytes,
        Err(e)
            if e.downcast_ref::<std::io::Error>()
                .is_some_and(|io| io.kind() == std::io::ErrorKind::NotFound) =>
        {
            return Ok(false);
        }
        Err(e) => return Err(e),
    };

    let remote_aad = format!("sync.attachment.bytes:{sha256}");
    let ciphertext = encrypt_bytes(sync_key, &plaintext, remote_aad.as_bytes())?;
    let remote_path = format!("{attachments_dir}{sha256}.bin");
    remote.put(&remote_path, ciphertext)?;
    Ok(true)
}

fn upload_all_local_embedding_artifact_blobs(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root_dir: &str,
    app_dir: &Path,
) -> Result<u64> {
    let artifacts_dir = format!("{remote_root_dir}embedding_artifacts/");
    remote.mkdir_all(&artifacts_dir)?;
    let existing = remote.list(&artifacts_dir)?;
    let existing: BTreeSet<String> = existing.into_iter().collect();

    let blob_refs = crate::db::list_distinct_embedding_artifact_blob_refs(conn)?;
    let mut uploaded = 0u64;
    for blob_ref in blob_refs {
        let rel_path = crate::db::embedding_artifact_blob_rel_path(&blob_ref);
        let remote_path = format!("{remote_root_dir}{rel_path}");
        if existing.contains(&remote_path) {
            continue;
        }
        if upload_embedding_artifact_blob_if_present(
            db_key,
            sync_key,
            remote,
            remote_root_dir,
            app_dir,
            &blob_ref,
        )? {
            uploaded += 1;
        }
    }
    Ok(uploaded)
}

fn upload_embedding_artifact_blob_if_present(
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root_dir: &str,
    app_dir: &Path,
    blob_ref: &str,
) -> Result<bool> {
    if !crate::db::has_embedding_artifact_blob(app_dir, blob_ref) {
        return Ok(false);
    }

    let plaintext = crate::db::read_embedding_artifact_blob(app_dir, db_key, blob_ref)?;
    let remote_aad = format!("sync.embedding_artifact.blob:{blob_ref}");
    let ciphertext = encrypt_bytes(sync_key, &plaintext, remote_aad.as_bytes())?;
    let remote_path = format!(
        "{remote_root_dir}{}",
        crate::db::embedding_artifact_blob_rel_path(blob_ref)
    );
    remote.put(&remote_path, ciphertext)?;
    Ok(true)
}

fn download_missing_embedding_artifact_blobs(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    let app_dir = crate::db::app_dir_from_conn(conn)?;
    let remote_root_dir = normalize_dir(remote_root);
    let mut downloaded = 0u64;

    for blob_ref in crate::db::list_distinct_embedding_artifact_blob_refs(conn)? {
        if crate::db::has_embedding_artifact_blob(app_dir.as_path(), &blob_ref) {
            continue;
        }
        let remote_path = format!(
            "{remote_root_dir}{}",
            crate::db::embedding_artifact_blob_rel_path(&blob_ref)
        );
        let ciphertext = match remote.get(&remote_path) {
            Ok(bytes) => bytes,
            Err(e) if e.is::<NotFound>() => continue,
            Err(e) => return Err(e),
        };
        let aad = format!("sync.embedding_artifact.blob:{blob_ref}");
        let plaintext = decrypt_bytes(sync_key, &ciphertext, aad.as_bytes())?;
        crate::db::write_embedding_artifact_blob(app_dir.as_path(), db_key, &blob_ref, &plaintext)?;
        downloaded += 1;
    }

    Ok(downloaded)
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(&mut out, "{b:02x}");
    }
    out
}

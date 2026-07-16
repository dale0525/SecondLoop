use crate::credential::{CredentialScope, SecretId, SecretMaterial, SecretStore};
use aes_gcm::aead::rand_core::RngCore;
use aes_gcm::aead::{Aead, KeyInit, OsRng, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use async_trait::async_trait;
use sha2::{Digest, Sha256};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use uuid::Uuid;

const ENVELOPE_MAGIC: &[u8; 8] = b"GASECR01";
const NONCE_BYTES: usize = 12;

pub struct EncryptedFileSecretStore {
    root: PathBuf,
    master_key: [u8; 32],
    mutation: Mutex<()>,
}

impl EncryptedFileSecretStore {
    pub fn new(root: impl Into<PathBuf>, master_key: SecretMaterial) -> anyhow::Result<Self> {
        Self::new_borrowed(root, &master_key)
    }

    /// Builds a store from borrowed startup key material without requiring the
    /// caller to create another secret-bearing allocation.
    pub fn new_borrowed(
        root: impl Into<PathBuf>,
        master_key: &SecretMaterial,
    ) -> anyhow::Result<Self> {
        anyhow::ensure!(
            master_key.expose_bytes().len() == 32,
            "secret store master key must be 32 bytes"
        );
        let root = root.into();
        prepare_private_root(&root)?;
        let mut key = [0u8; 32];
        key.copy_from_slice(master_key.expose_bytes());
        Ok(Self {
            root,
            master_key: key,
            mutation: Mutex::new(()),
        })
    }

    fn path(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<PathBuf> {
        scope.validate()?;
        let identity = serde_json::to_vec(&(
            &scope.app_id,
            &scope.tenant_id,
            &scope.user_id,
            secret_id.as_str(),
        ))?;
        Ok(self
            .root
            .join(format!("{}.secret", hex::encode(Sha256::digest(identity)))))
    }

    fn encrypt(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: &SecretMaterial,
    ) -> anyhow::Result<Vec<u8>> {
        let cipher = Aes256Gcm::new_from_slice(&self.master_key)
            .map_err(|_| anyhow::anyhow!("secret store key is invalid"))?;
        let mut nonce = [0u8; NONCE_BYTES];
        OsRng.fill_bytes(&mut nonce);
        let ciphertext = cipher
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: value.expose_bytes(),
                    aad: &associated_data(scope, secret_id)?,
                },
            )
            .map_err(|_| anyhow::anyhow!("secret encryption failed"))?;
        let mut envelope =
            Vec::with_capacity(ENVELOPE_MAGIC.len() + NONCE_BYTES + ciphertext.len());
        envelope.extend_from_slice(ENVELOPE_MAGIC);
        envelope.extend_from_slice(&nonce);
        envelope.extend_from_slice(&ciphertext);
        Ok(envelope)
    }

    fn decrypt(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        envelope: &[u8],
    ) -> anyhow::Result<SecretMaterial> {
        anyhow::ensure!(
            envelope.len() > ENVELOPE_MAGIC.len() + NONCE_BYTES
                && &envelope[..ENVELOPE_MAGIC.len()] == ENVELOPE_MAGIC,
            "secret envelope is invalid"
        );
        let nonce_start = ENVELOPE_MAGIC.len();
        let ciphertext_start = nonce_start + NONCE_BYTES;
        let cipher = Aes256Gcm::new_from_slice(&self.master_key)
            .map_err(|_| anyhow::anyhow!("secret store key is invalid"))?;
        let plaintext = cipher
            .decrypt(
                Nonce::from_slice(&envelope[nonce_start..ciphertext_start]),
                Payload {
                    msg: &envelope[ciphertext_start..],
                    aad: &associated_data(scope, secret_id)?,
                },
            )
            .map_err(|_| anyhow::anyhow!("secret envelope authentication failed"))?;
        SecretMaterial::new(plaintext)
    }

    fn write_secret(&self, path: &Path, envelope: &[u8], replace: bool) -> anyhow::Result<()> {
        let temporary = self.root.join(format!(".secret-{}.tmp", Uuid::new_v4()));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&temporary)?;
        file.write_all(envelope)?;
        file.sync_all()?;
        if !replace && path.exists() {
            let _ = std::fs::remove_file(&temporary);
            anyhow::bail!("secret already exists");
        }
        if let Err(error) = std::fs::rename(&temporary, path) {
            let _ = std::fs::remove_file(&temporary);
            return Err(error.into());
        }
        sync_directory(&self.root)?;
        Ok(())
    }
}

impl Drop for EncryptedFileSecretStore {
    fn drop(&mut self) {
        self.master_key.fill(0);
    }
}

#[async_trait]
impl SecretStore for EncryptedFileSecretStore {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        let _guard = self.mutation.lock().expect("secret store lock poisoned");
        let path = self.path(scope, secret_id)?;
        reject_symlink(&path)?;
        self.write_secret(&path, &self.encrypt(scope, secret_id, &value)?, false)
    }

    async fn load(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>> {
        let path = self.path(scope, secret_id)?;
        reject_symlink(&path)?;
        let file = match File::open(&path) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        let mut envelope = Vec::new();
        file.take(128 * 1024).read_to_end(&mut envelope)?;
        Ok(Some(self.decrypt(scope, secret_id, &envelope)?))
    }

    async fn delete(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<bool> {
        let _guard = self.mutation.lock().expect("secret store lock poisoned");
        let path = self.path(scope, secret_id)?;
        reject_symlink(&path)?;
        match std::fs::remove_file(path) {
            Ok(()) => {
                sync_directory(&self.root)?;
                Ok(true)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(error) => Err(error.into()),
        }
    }

    async fn rotate(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        let _guard = self.mutation.lock().expect("secret store lock poisoned");
        let path = self.path(scope, secret_id)?;
        reject_symlink(&path)?;
        anyhow::ensure!(path.is_file(), "secret does not exist");
        self.write_secret(&path, &self.encrypt(scope, secret_id, &value)?, true)
    }
}

fn associated_data(scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<Vec<u8>> {
    Ok(serde_json::to_vec(&(
        "agentweave.secret.v1",
        &scope.app_id,
        &scope.tenant_id,
        &scope.user_id,
        secret_id.as_str(),
    ))?)
}

fn prepare_private_root(root: &Path) -> anyhow::Result<()> {
    if let Ok(metadata) = std::fs::symlink_metadata(root) {
        anyhow::ensure!(metadata.is_dir(), "secret store root must be a directory");
        anyhow::ensure!(
            !metadata.file_type().is_symlink(),
            "secret store root cannot be a symlink"
        );
    } else {
        std::fs::create_dir_all(root)?;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(root, std::fs::Permissions::from_mode(0o700))?;
    }
    sync_directory(root)
}

fn reject_symlink(path: &Path) -> anyhow::Result<()> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) => anyhow::ensure!(
            !metadata.file_type().is_symlink(),
            "secret path cannot be a symlink"
        ),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

fn sync_directory(path: &Path) -> anyhow::Result<()> {
    File::open(path)?.sync_all()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn scope(app_id: &str) -> CredentialScope {
        CredentialScope {
            app_id: app_id.into(),
            tenant_id: "tenant".into(),
            user_id: "user".into(),
        }
    }

    #[tokio::test]
    async fn encrypted_store_persists_rotates_and_is_scope_bound() {
        let directory = TempDir::new().unwrap();
        let root = directory.path().join("secrets");
        let key = vec![7u8; 32];
        let id = SecretId::parse("mail.primary").unwrap();
        {
            let store =
                EncryptedFileSecretStore::new(&root, SecretMaterial::new(key.clone()).unwrap())
                    .unwrap();
            store
                .save(
                    &scope("app-a"),
                    &id,
                    SecretMaterial::new("secret-value").unwrap(),
                )
                .await
                .unwrap();
            let bytes = std::fs::read(
                std::fs::read_dir(&root)
                    .unwrap()
                    .next()
                    .unwrap()
                    .unwrap()
                    .path(),
            )
            .unwrap();
            assert!(!bytes.windows(12).any(|window| window == b"secret-value"));
        }
        let borrowed_key = SecretMaterial::new(key).unwrap();
        let store = EncryptedFileSecretStore::new_borrowed(&root, &borrowed_key).unwrap();
        assert_eq!(
            store
                .load(&scope("app-a"), &id)
                .await
                .unwrap()
                .unwrap()
                .expose_bytes(),
            b"secret-value"
        );
        assert!(store.load(&scope("app-b"), &id).await.unwrap().is_none());
        store
            .rotate(
                &scope("app-a"),
                &id,
                SecretMaterial::new("new-value").unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            store
                .load(&scope("app-a"), &id)
                .await
                .unwrap()
                .unwrap()
                .expose_bytes(),
            b"new-value"
        );
        assert!(store.delete(&scope("app-a"), &id).await.unwrap());
        assert!(store.load(&scope("app-a"), &id).await.unwrap().is_none());
    }
}

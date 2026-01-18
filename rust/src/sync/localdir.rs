use std::collections::BTreeSet;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};

fn normalize_dir(path: &str) -> String {
    let trimmed = path.trim_matches('/');
    if trimmed.is_empty() {
        return "/".to_string();
    }
    format!("/{trimmed}/")
}

fn normalize_file(path: &str) -> String {
    let trimmed = path.trim_matches('/');
    format!("/{trimmed}")
}

fn virtual_to_local(root: &Path, virtual_path: &str) -> PathBuf {
    let relative = virtual_path.trim_start_matches('/');
    root.join(relative)
}

#[derive(Clone, Debug)]
pub struct LocalDirRemoteStore {
    root: PathBuf,
    target_id: String,
}

impl LocalDirRemoteStore {
    pub fn new(root: PathBuf) -> Result<Self> {
        fs::create_dir_all(&root)?;
        let canonical = root.canonicalize().unwrap_or_else(|_| root.clone());
        let target_id = format!("localdir:{}", canonical.to_string_lossy());
        Ok(Self { root, target_id })
    }
}

impl super::RemoteStore for LocalDirRemoteStore {
    fn target_id(&self) -> &str {
        &self.target_id
    }

    fn mkdir_all(&self, path: &str) -> Result<()> {
        let dir = normalize_dir(path);
        if dir == "/" {
            return Ok(());
        }
        let local = virtual_to_local(&self.root, dir.trim_end_matches('/'));
        fs::create_dir_all(local)?;
        Ok(())
    }

    fn list(&self, dir: &str) -> Result<Vec<String>> {
        let dir = normalize_dir(dir);
        let local = virtual_to_local(&self.root, dir.trim_end_matches('/'));
        if !local.exists() {
            return Ok(vec![]);
        }

        let mut out: BTreeSet<String> = BTreeSet::new();
        for entry in fs::read_dir(local)? {
            let entry = entry?;
            let file_type = entry.file_type()?;
            let name_os = entry.file_name();
            let Some(name) = name_os.to_str() else {
                continue;
            };
            if name.is_empty() {
                continue;
            }
            if file_type.is_dir() {
                out.insert(format!("{dir}{name}/"));
            } else {
                out.insert(format!("{dir}{name}"));
            }
        }

        Ok(out.into_iter().collect())
    }

    fn get(&self, path: &str) -> Result<Vec<u8>> {
        let path = normalize_file(path);
        if path.ends_with('/') {
            return Err(anyhow!("GET expects file path, got dir: {path}"));
        }

        let local = virtual_to_local(&self.root, path.trim_start_matches('/'));
        match fs::read(local) {
            Ok(bytes) => Ok(bytes),
            Err(e) if e.kind() == ErrorKind::NotFound => Err(super::NotFound { path }.into()),
            Err(e) => Err(e.into()),
        }
    }

    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()> {
        let path = normalize_file(path);
        if path.ends_with('/') {
            return Err(anyhow!("PUT expects file path, got dir: {path}"));
        }

        let local = virtual_to_local(&self.root, path.trim_start_matches('/'));
        if let Some(parent) = local.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(local, bytes)?;
        Ok(())
    }

    fn delete(&self, path: &str) -> Result<()> {
        if path.ends_with('/') {
            let dir = normalize_dir(path);
            if dir == "/" {
                return Err(anyhow!("refusing to delete root dir"));
            }

            let local = virtual_to_local(&self.root, dir.trim_end_matches('/'));
            match fs::remove_dir_all(local) {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == ErrorKind::NotFound => Err(super::NotFound { path: dir }.into()),
                Err(e) => Err(e.into()),
            }
        } else {
            let file = normalize_file(path);
            if file.ends_with('/') {
                return Err(anyhow!("DELETE expects file path, got dir: {file}"));
            }

            let local = virtual_to_local(&self.root, file.trim_start_matches('/'));
            match fs::remove_file(local) {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == ErrorKind::NotFound => {
                    Err(super::NotFound { path: file }.into())
                }
                Err(e) => Err(e.into()),
            }
        }
    }
}

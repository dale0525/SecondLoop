use std::collections::BTreeSet;
use std::fs;
use std::io::ErrorKind;
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{anyhow, Result};

static LOCALDIR_TMP_SEQ: AtomicU64 = AtomicU64::new(1);

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

fn parse_relative_virtual_path(virtual_path: &str) -> Result<PathBuf> {
    let trimmed = virtual_path.trim_start_matches('/');
    let mut relative = PathBuf::new();
    for component in Path::new(trimmed).components() {
        match component {
            Component::Normal(part) => relative.push(part),
            Component::CurDir => {}
            Component::ParentDir => {
                return Err(anyhow!("path traversal is not allowed: {virtual_path}"));
            }
            _ => {
                return Err(anyhow!("absolute path is not allowed: {virtual_path}"));
            }
        }
    }
    Ok(relative)
}

#[derive(Clone, Debug)]
pub struct LocalDirRemoteStore {
    root: PathBuf,
    target_id: String,
}

impl LocalDirRemoteStore {
    pub fn new(root: PathBuf) -> Result<Self> {
        fs::create_dir_all(&root)?;
        let canonical = root.canonicalize().unwrap_or(root);
        let target_id = format!("localdir:{}", canonical.to_string_lossy());
        Ok(Self {
            root: canonical,
            target_id,
        })
    }

    fn resolve_virtual_path(&self, virtual_path: &str) -> Result<PathBuf> {
        let relative = parse_relative_virtual_path(virtual_path)?;
        let local = self.root.join(relative);
        self.ensure_within_root(&local)?;
        Ok(local)
    }

    fn ensure_within_root(&self, local: &Path) -> Result<()> {
        let mut existing = local;
        loop {
            if existing.exists() {
                let canonical = existing.canonicalize()?;
                if canonical.starts_with(&self.root) {
                    return Ok(());
                }
                return Err(anyhow!("path escapes localdir root: {}", local.display()));
            }
            existing = existing
                .parent()
                .ok_or_else(|| anyhow!("invalid path: {}", local.display()))?;
        }
    }

    fn atomic_write_file(&self, local: &Path, bytes: &[u8]) -> Result<()> {
        let Some(parent) = local.parent() else {
            return Err(anyhow!("invalid localdir file path: {}", local.display()));
        };
        fs::create_dir_all(parent)?;

        let seq = LOCALDIR_TMP_SEQ.fetch_add(1, Ordering::Relaxed);
        let tmp_name = format!(".secondloop_tmp_{seq}.bin");
        let tmp_path = parent.join(tmp_name);
        self.ensure_within_root(&tmp_path)?;

        let write_result: Result<()> = (|| {
            let mut file = fs::OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(&tmp_path)?;
            file.write_all(bytes)?;
            file.sync_all()?;

            match fs::rename(&tmp_path, local) {
                Ok(()) => {}
                Err(e) if e.kind() == ErrorKind::AlreadyExists => {
                    fs::remove_file(local)?;
                    fs::rename(&tmp_path, local)?;
                }
                Err(e) => return Err(e.into()),
            }

            #[cfg(unix)]
            {
                if let Ok(dir_handle) = fs::File::open(parent) {
                    let _ = dir_handle.sync_all();
                }
            }

            Ok(())
        })();

        if write_result.is_err() {
            let _ = fs::remove_file(&tmp_path);
        }
        write_result
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
        let local = self.resolve_virtual_path(dir.trim_end_matches('/'))?;
        fs::create_dir_all(local)?;
        Ok(())
    }

    fn list(&self, dir: &str) -> Result<Vec<String>> {
        let dir = normalize_dir(dir);
        let local = self.resolve_virtual_path(dir.trim_end_matches('/'))?;
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

    fn exists(&self, path: &str) -> Result<bool> {
        if path.ends_with('/') {
            let dir = normalize_dir(path);
            let local = self.resolve_virtual_path(dir.trim_end_matches('/'))?;
            return Ok(local.is_dir());
        }

        let path = normalize_file(path);
        let local = self.resolve_virtual_path(path.trim_start_matches('/'))?;
        Ok(local.is_file())
    }

    fn get(&self, path: &str) -> Result<Vec<u8>> {
        let path = normalize_file(path);
        if path.ends_with('/') {
            return Err(anyhow!("GET expects file path, got dir: {path}"));
        }

        let local = self.resolve_virtual_path(path.trim_start_matches('/'))?;
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

        let local = self.resolve_virtual_path(path.trim_start_matches('/'))?;
        self.atomic_write_file(&local, &bytes)
    }

    fn delete(&self, path: &str) -> Result<()> {
        if path.ends_with('/') {
            let dir = normalize_dir(path);
            if dir == "/" {
                return Err(anyhow!("refusing to delete root dir"));
            }

            let local = self.resolve_virtual_path(dir.trim_end_matches('/'))?;
            match fs::remove_dir_all(local) {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == ErrorKind::NotFound => {
                    Err(super::NotFound { path: dir }.into())
                }
                Err(e) => Err(e.into()),
            }
        } else {
            let file = normalize_file(path);
            if file.ends_with('/') {
                return Err(anyhow!("DELETE expects file path, got dir: {file}"));
            }

            let local = self.resolve_virtual_path(file.trim_start_matches('/'))?;
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

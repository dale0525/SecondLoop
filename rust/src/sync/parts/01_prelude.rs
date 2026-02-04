use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::thread;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

#[derive(Debug)]
pub struct NotFound {
    pub path: String,
}

impl std::fmt::Display for NotFound {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "not found: {}", self.path)
    }
}

impl std::error::Error for NotFound {}

pub trait RemoteStore: Send + Sync {
    fn target_id(&self) -> &str;
    fn mkdir_all(&self, path: &str) -> Result<()>;
    fn list(&self, dir: &str) -> Result<Vec<String>>;
    fn get(&self, path: &str) -> Result<Vec<u8>>;
    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()>;
    fn delete(&self, path: &str) -> Result<()>;
}

const OPS_PACK_CHUNK_SIZE: i64 = 500;
const OPS_PACK_MAGIC_V1: &[u8; 5] = b"SLPK1";

static INMEM_NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub struct InMemoryRemoteStore {
    target_id: String,
    dirs: Mutex<BTreeSet<String>>,
    files: Mutex<BTreeMap<String, Vec<u8>>>,
}

impl InMemoryRemoteStore {
    pub fn new() -> Self {
        let id = INMEM_NEXT_ID.fetch_add(1, Ordering::Relaxed);
        Self {
            target_id: format!("inmem:{id}"),
            dirs: Mutex::new(BTreeSet::new()),
            files: Mutex::new(BTreeMap::new()),
        }
    }
}

impl Default for InMemoryRemoteStore {
    fn default() -> Self {
        Self::new()
    }
}

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

fn sync_scope_id(remote: &impl RemoteStore, remote_root_dir: &str) -> String {
    let scope = format!("{}|{remote_root_dir}", remote.target_id());
    B64_URL.encode(scope.as_bytes())
}

impl RemoteStore for InMemoryRemoteStore {
    fn target_id(&self) -> &str {
        &self.target_id
    }

    fn mkdir_all(&self, path: &str) -> Result<()> {
        let dir = normalize_dir(path);
        let mut dirs = self.dirs.lock().map_err(|_| anyhow!("poisoned lock"))?;
        // Add all parent dirs.
        let mut cur = "/".to_string();
        dirs.insert(cur.clone());
        for part in dir.trim_matches('/').split('/') {
            if part.is_empty() {
                continue;
            }
            cur.push_str(part);
            cur.push('/');
            dirs.insert(cur.clone());
        }
        Ok(())
    }

    fn list(&self, dir: &str) -> Result<Vec<String>> {
        let dir = normalize_dir(dir);
        let dirs = self.dirs.lock().map_err(|_| anyhow!("poisoned lock"))?;
        let files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;

        if !dirs.contains(&dir) {
            return Ok(vec![]);
        }

        let mut out: BTreeSet<String> = BTreeSet::new();

        for d in dirs.iter() {
            if d == &dir {
                continue;
            }
            if let Some(rest) = d.strip_prefix(&dir) {
                if rest.is_empty() {
                    continue;
                }
                let mut parts = rest.split('/').filter(|p| !p.is_empty());
                if let Some(first) = parts.next() {
                    out.insert(format!("{dir}{first}/"));
                }
            }
        }

        for f in files.keys() {
            if let Some(rest) = f.strip_prefix(&dir) {
                if rest.is_empty() {
                    continue;
                }
                let mut parts = rest.split('/').filter(|p| !p.is_empty());
                if let Some(first) = parts.next() {
                    if parts.next().is_none() {
                        out.insert(format!("{dir}{first}"));
                    } else {
                        out.insert(format!("{dir}{first}/"));
                    }
                }
            }
        }

        Ok(out.into_iter().collect())
    }

    fn get(&self, path: &str) -> Result<Vec<u8>> {
        let path = normalize_file(path);
        let files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;
        files
            .get(&path)
            .cloned()
            .ok_or_else(|| NotFound { path }.into())
    }

    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()> {
        let path = normalize_file(path);
        let mut files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;
        files.insert(path, bytes);
        Ok(())
    }

    fn delete(&self, path: &str) -> Result<()> {
        if path.ends_with('/') {
            let dir = normalize_dir(path);
            if dir == "/" {
                return Err(anyhow!("refusing to delete root dir"));
            }

            let mut dirs = self.dirs.lock().map_err(|_| anyhow!("poisoned lock"))?;
            let mut files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;

            if !dirs.contains(&dir) {
                return Err(NotFound { path: dir }.into());
            }

            let to_remove: Vec<String> = files
                .keys()
                .filter(|k| k.starts_with(&dir))
                .cloned()
                .collect();
            for key in to_remove {
                files.remove(&key);
            }

            let dirs_to_remove: Vec<String> = dirs
                .iter()
                .filter(|d| d.starts_with(&dir))
                .cloned()
                .collect();
            for d in dirs_to_remove {
                dirs.remove(&d);
            }

            Ok(())
        } else {
            let file = normalize_file(path);
            let mut files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;
            if files.remove(&file).is_none() {
                return Err(NotFound { path: file }.into());
            }
            Ok(())
        }
    }
}


#[flutter_rust_bridge::frb]
pub fn sync_create_recovery_envelope(sync_key: Vec<u8>, passphrase: String) -> Result<String> {
    let sync_key = sync_key_from_bytes(sync_key)?;
    let envelope = sync::recovery_key::create_recovery_envelope(&sync_key, &passphrase)?;
    serde_json::to_string(&envelope).map_err(|e| anyhow!("serialize recovery envelope failed: {e}"))
}

#[flutter_rust_bridge::frb]
pub fn sync_recover_sync_key_from_envelope(
    envelope_json: String,
    passphrase: String,
) -> Result<Vec<u8>> {
    let envelope: sync::recovery_key::RecoveryEnvelope =
        serde_json::from_str(&envelope_json).map_err(|_| anyhow!("invalid recovery envelope"))?;
    let key = sync::recovery_key::recover_sync_key(&envelope, &passphrase)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_test_connection(
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<()> {
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    remote.mkdir_all(&remote_root)?;
    remote.ensure_dir_exists(&remote_root)?;
    let _ = remote.list(&remote_root)?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::push(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push_ops_only(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::push_ops_only(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::pull(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_download_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
    sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::download_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
        .map_err(map_attachment_download_error)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_upload_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
    sha256: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::upload_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_clear_remote_root(
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<()> {
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::clear_remote_root(&remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_test_connection(local_dir: String, remote_root: String) -> Result<()> {
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    remote.mkdir_all(&remote_root)?;
    let _ = remote.list(&remote_root)?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::push(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_push_ops_only(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::push_ops_only(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::pull(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_download_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
    sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::download_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
        .map_err(map_attachment_download_error)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_upload_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
    sha256: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::upload_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_clear_remote_root(local_dir: String, remote_root: String) -> Result<()> {
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::clear_remote_root(&remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::push(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push_ops_only(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::push_ops_only(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
    )
}

#[flutter_rust_bridge::frb]
pub async fn sync_managed_vault_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    #[cfg(not(target_family = "wasm"))]
    {
        let run_pull = move || {
            let conn = db::open(Path::new(&app_dir))?;
            sync::managed_vault::pull(
                &conn,
                &key,
                &sync_key,
                &base_url,
                &vault_id,
                &firebase_id_token,
            )
        };
        return tokio::task::spawn_blocking(run_pull)
            .await
            .map_err(|error| anyhow!("sync_managed_vault_pull task failed: {error}"))?;
    }
    #[cfg(target_family = "wasm")]
    {
        let conn = db::open(Path::new(&app_dir))?;
        sync::managed_vault::pull(
            &conn,
            &key,
            &sync_key,
            &base_url,
            &vault_id,
            &firebase_id_token,
        )
    }
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_upload_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    sha256: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::upload_attachment_bytes(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
        &sha256,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_download_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::download_attachment_bytes(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
        &sha256,
    )
    .map_err(map_attachment_download_error)
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_clear_device(
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    device_id: String,
) -> Result<()> {
    sync::managed_vault::clear_device(&base_url, &vault_id, &firebase_id_token, &device_id)
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_clear_vault(
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<()> {
    sync::managed_vault::clear_vault(&base_url, &vault_id, &firebase_id_token)
}

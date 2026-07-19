use std::path::{Path, PathBuf};

pub(super) async fn make_test_tree_writable(root: &Path) {
    let mut entries = tokio::fs::read_dir(root).await.unwrap();
    while let Some(entry) = entries.next_entry().await.unwrap() {
        let mut permissions = entry.metadata().await.unwrap().permissions();
        set_test_writable(&mut permissions, false);
        tokio::fs::set_permissions(entry.path(), permissions)
            .await
            .unwrap();
    }
    let mut permissions = tokio::fs::metadata(root).await.unwrap().permissions();
    set_test_writable(&mut permissions, true);
    tokio::fs::set_permissions(root, permissions).await.unwrap();
}

pub(super) fn unique_test_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("agentweave-main-{name}-{}", uuid::Uuid::new_v4()))
}

pub(super) async fn remove_test_dir(path: PathBuf) {
    if path.exists() {
        let mut stack = vec![path.clone()];
        while let Some(current) = stack.pop() {
            let mut permissions = tokio::fs::symlink_metadata(&current)
                .await
                .unwrap()
                .permissions();
            set_test_writable(&mut permissions, current.is_dir());
            tokio::fs::set_permissions(&current, permissions)
                .await
                .unwrap();
            if current.is_dir() {
                let mut entries = tokio::fs::read_dir(&current).await.unwrap();
                while let Some(entry) = entries.next_entry().await.unwrap() {
                    stack.push(entry.path());
                }
            }
        }
        tokio::fs::remove_dir_all(path).await.unwrap();
    }
}

fn set_test_writable(permissions: &mut std::fs::Permissions, directory: bool) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let owner_access = if directory { 0o700 } else { 0o600 };
        permissions.set_mode(permissions.mode() | owner_access);
    }
    #[cfg(not(unix))]
    permissions.set_readonly(false);
}

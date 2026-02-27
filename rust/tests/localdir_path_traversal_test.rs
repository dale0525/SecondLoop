use secondloop_rust::sync::localdir::LocalDirRemoteStore;
use secondloop_rust::sync::RemoteStore;

#[test]
fn localdir_rejects_parent_dir_traversal_on_write_and_read() {
    let root = tempfile::tempdir().expect("root");
    let outside = tempfile::tempdir().expect("outside");
    let outside_file = outside.path().join("escape.txt");

    let remote =
        LocalDirRemoteStore::new(root.path().to_path_buf()).expect("create localdir remote");

    let write_err = remote
        .put("/../../escape.txt", b"pwn".to_vec())
        .expect_err("write traversal must be rejected");
    let write_msg = write_err.to_string();
    assert!(
        write_msg.contains("traversal")
            || write_msg.contains("escapes")
            || write_msg.contains("outside"),
        "unexpected write error: {write_msg}"
    );
    assert!(!outside_file.exists(), "outside file must not be created");

    let read_err = remote
        .get("/../../escape.txt")
        .expect_err("read traversal must be rejected");
    let read_msg = read_err.to_string();
    assert!(
        read_msg.contains("traversal")
            || read_msg.contains("escapes")
            || read_msg.contains("outside"),
        "unexpected read error: {read_msg}"
    );
}

#[cfg(unix)]
#[test]
fn localdir_rejects_symlink_escape_on_write() {
    use std::os::unix::fs::symlink;

    let root = tempfile::tempdir().expect("root");
    let outside = tempfile::tempdir().expect("outside");

    let escape_link = root.path().join("escape-link");
    symlink(outside.path(), &escape_link).expect("create symlink");

    let remote =
        LocalDirRemoteStore::new(root.path().to_path_buf()).expect("create localdir remote");

    let err = remote
        .put("/escape-link/evil.bin", vec![1, 2, 3])
        .expect_err("symlink escape must be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("escapes") || msg.contains("outside") || msg.contains("traversal"),
        "unexpected error: {msg}"
    );

    assert!(
        !outside.path().join("evil.bin").exists(),
        "outside file must not be created"
    );
}

#[test]
fn localdir_allows_valid_paths() {
    let root = tempfile::tempdir().expect("root");
    let remote =
        LocalDirRemoteStore::new(root.path().to_path_buf()).expect("create localdir remote");

    remote
        .put("/safe/hello.txt", b"ok".to_vec())
        .expect("write valid path");

    let got = remote.get("/safe/hello.txt").expect("read valid path");
    assert_eq!(got, b"ok");
}

#[test]
fn localdir_put_atomically_overwrites_existing_file() {
    let root = tempfile::tempdir().expect("root");
    let remote =
        LocalDirRemoteStore::new(root.path().to_path_buf()).expect("create localdir remote");

    remote
        .put("/safe/atomic.txt", b"v1".to_vec())
        .expect("write v1");
    remote
        .put("/safe/atomic.txt", b"v2-updated".to_vec())
        .expect("write v2");

    let got = remote.get("/safe/atomic.txt").expect("read latest");
    assert_eq!(got, b"v2-updated");
}

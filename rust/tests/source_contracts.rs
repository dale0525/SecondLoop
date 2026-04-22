use std::fs;
use std::path::{Path, PathBuf};

fn collect_rust_files(root: &Path, out: &mut Vec<PathBuf>) {
    let entries = fs::read_dir(root).expect("read dir");
    for entry in entries {
        let entry = entry.expect("dir entry");
        let path = entry.path();
        if path.is_dir() {
            collect_rust_files(&path, out);
            continue;
        }
        if path.extension().and_then(|ext| ext.to_str()) == Some("rs") {
            out.push(path);
        }
    }
}

#[test]
fn sync_checklist_apply_does_not_toggle_foreign_keys_inside_apply_flow() {
    let source = include_str!("../src/sync/parts/04b_apply_todo_checklist.rs");

    assert!(
        !source.contains("PRAGMA foreign_keys = OFF;"),
        "sync checklist apply should rely on pending_apply for out-of-order dependencies instead of toggling FK state inside transactions",
    );
}

#[test]
fn vendored_flutter_rust_bridge_uses_standard_target_family_cfgs() {
    let crate_root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let frb_src_root = crate_root.join("../third_party/flutter-rust-bridge-patched/src");

    let mut rust_files = Vec::new();
    collect_rust_files(&frb_src_root, &mut rust_files);
    rust_files.sort();

    let mut offenders = Vec::new();
    for path in rust_files {
        let source = fs::read_to_string(&path).expect("read rust source");
        if source.contains("#[cfg(wasm)]") || source.contains("#[cfg(not(wasm))]") {
            offenders.push(path);
        }
    }

    assert!(
        offenders.is_empty(),
        "vendored flutter_rust_bridge should not use cfg(wasm): {offenders:?}",
    );
}

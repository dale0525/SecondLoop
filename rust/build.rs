use std::process::Command;

fn main() {
    println!("cargo:rustc-check-cfg=cfg(frb_expand)");
    println!("cargo:rerun-if-env-changed=DEVELOPER_DIR");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os != "macos" {
        return;
    }

    let output = match Command::new("xcrun")
        .args([
            "--toolchain",
            "XcodeDefault.xctoolchain",
            "clang",
            "--print-runtime-dir",
        ])
        .output()
    {
        Ok(output) if output.status.success() => output,
        _ => return,
    };

    let runtime_dir = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if runtime_dir.is_empty() {
        return;
    }

    println!("cargo:rustc-link-search=native={runtime_dir}");
    println!("cargo:rustc-link-lib=clang_rt.osx");
}

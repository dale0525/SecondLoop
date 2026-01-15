fn main() {
    // Used by flutter_rust_bridge_codegen when expanding macros.
    println!("cargo:rustc-check-cfg=cfg(frb_expand)");
}

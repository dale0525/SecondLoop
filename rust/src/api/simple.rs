#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub async fn init_app() -> anyhow::Result<()> {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
    #[cfg(target_family = "wasm")]
    console_error_panic_hook::set_once();
    crate::platform::sqlite_runtime::ensure_ready().await
}

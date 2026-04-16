#[cfg(not(target_family = "wasm"))]
pub fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(i64::MAX)
}

#[cfg(target_family = "wasm")]
pub fn now_ms() -> i64 {
    let millis = js_sys::Date::now();
    if !millis.is_finite() {
        return 0;
    }
    millis.clamp(0.0, i64::MAX as f64) as i64
}

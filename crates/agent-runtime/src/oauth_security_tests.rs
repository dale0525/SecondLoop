use super::*;

#[test]
fn secret_debug_is_redacted_and_callback_urls_are_loopback_bound() {
    let secret = OAuthSecretString::new("secret-value".into()).unwrap();
    assert_eq!(format!("{secret:?}"), "OAuthSecretString([REDACTED])");
    let now = Utc::now();
    let start = OAuthAuthorizationStart {
        authorization_id: "authorization".into(),
        provider_id: "workspace".into(),
        connector_ids: BTreeSet::from(["calendar".into()]),
        requested_capabilities: BTreeSet::from(["read".into()]),
        status: OAuthAuthorizationStatus::Pending,
        expires_at: now,
        authorization_url: "https://accounts.example.test/?state=secret-state".into(),
        authorization_origin: "https://accounts.example.test".into(),
    };
    let start_debug = format!("{start:?}");
    assert!(start_debug.contains("[REDACTED]"));
    assert!(!start_debug.contains("secret-state"));
    let url_request = OAuthAuthorizationUrlRequest {
        authorization_id: "authorization".into(),
        redirect_uri: "http://127.0.0.1:9000/oauth/callback".into(),
        state: "secret-state".into(),
        pkce_challenge: "secret-challenge".into(),
        scopes: BTreeSet::from(["calendar.read".into()]),
    };
    let request_debug = format!("{url_request:?}");
    assert!(!request_debug.contains("secret-state"));
    assert!(!request_debug.contains("secret-challenge"));
    assert!(validate_callback_url("http://127.0.0.1:9000/oauth/callback").is_ok());
    assert!(validate_callback_url("http://localhost:9000/oauth/callback").is_err());
    assert!(validate_callback_url("https://example.test/oauth/callback").is_err());
    assert!(validate_callback_url("http://127.0.0.1:9000/wrong").is_err());
    assert!(validate_callback_url("http://attacker.example/oauth/callback").is_err());
    assert!(validate_callback_url("file:///tmp/callback").is_err());
}

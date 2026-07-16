use super::*;

#[test]
fn request_debug_redacts_password() {
    let password = "debug-credential-marker";
    let request: MailAccountConfigurationRequest = serde_json::from_value(serde_json::json!({
        "displayName": "Primary Mail",
        "primaryName": "Local User",
        "primaryAddress": "user@example.test",
        "username": "user@example.test",
        "password": password,
        "imapHost": "imap.example.test",
        "imapPort": 993,
        "imapTls": "implicit",
        "smtpHost": "smtp.example.test",
        "smtpPort": 587,
        "smtpTls": "start_tls"
    }))
    .unwrap();

    let debug = format!("{request:?}");

    assert!(!debug.contains(password));
    assert!(debug.contains("[REDACTED]"));
}

use secondloop_rust::api::core;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::sync::recovery_key;

#[test]
fn recovery_envelope_roundtrip() {
    let sync_key = [42u8; 32];
    let passphrase = "correct horse battery staple";
    let salt = [9u8; 16];
    let kdf = KdfParams::for_test();

    let envelope =
        recovery_key::create_recovery_envelope_with_params(&sync_key, passphrase, &salt, &kdf)
            .expect("create envelope");
    let recovered = recovery_key::recover_sync_key(&envelope, passphrase).expect("recover key");
    assert_eq!(recovered, sync_key);
}

#[test]
fn recovery_envelope_uses_random_salt() {
    let sync_key = [7u8; 32];
    let passphrase = "same-passphrase";

    let a = recovery_key::create_recovery_envelope(&sync_key, passphrase).expect("envelope a");
    let b = recovery_key::create_recovery_envelope(&sync_key, passphrase).expect("envelope b");

    assert_ne!(a.kdf.salt_b64, b.kdf.salt_b64);
    assert_ne!(a.wrapped_sync_key_b64, b.wrapped_sync_key_b64);
}

#[test]
fn recovery_envelope_rejects_wrong_passphrase() {
    let sync_key = [1u8; 32];
    let passphrase = "right-passphrase";
    let envelope =
        recovery_key::create_recovery_envelope(&sync_key, passphrase).expect("create envelope");

    let err = recovery_key::recover_sync_key(&envelope, "wrong-passphrase")
        .expect_err("wrong passphrase should fail");
    let msg = err.to_string();
    assert!(
        msg.contains("decrypt failed") || msg.contains("argon2 hash"),
        "unexpected error: {msg}"
    );
}

#[test]
fn legacy_sync_derive_key_remains_backward_compatible() {
    let passphrase = "legacy-passphrase";
    let derived = core::sync_derive_key(passphrase.to_string()).expect("derive via api");
    let expected = derive_root_key(
        passphrase,
        b"secondloop-sync1",
        &KdfParams {
            m_cost_kib: 8 * 1024,
            t_cost: 2,
            p_cost: 1,
        },
    )
    .expect("derive expected");
    assert_eq!(derived, expected.to_vec());
}

#[test]
fn recovery_envelope_core_api_roundtrip() {
    let sync_key = vec![5u8; 32];
    let passphrase = "api-passphrase";

    let envelope_json =
        core::sync_create_recovery_envelope(sync_key.clone(), passphrase.to_string())
            .expect("create envelope via api");
    let recovered =
        core::sync_recover_sync_key_from_envelope(envelope_json, passphrase.to_string())
            .expect("recover via api");
    assert_eq!(recovered, sync_key);
}

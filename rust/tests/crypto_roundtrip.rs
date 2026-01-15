use secondloop_rust::crypto::{decrypt_bytes, derive_root_key, encrypt_bytes, KdfParams};

#[test]
fn crypto_roundtrip_encrypt_decrypt() {
    let password = "correct horse battery staple";
    let salt = [7u8; 16];
    let params = KdfParams::for_test();

    let key = derive_root_key(password, &salt, &params).expect("derive key");

    let plaintext = b"hello secondloop";
    let aad = b"unit-test";

    let blob = encrypt_bytes(&key, plaintext, aad).expect("encrypt");
    let decrypted = decrypt_bytes(&key, &blob, aad).expect("decrypt");
    assert_eq!(decrypted, plaintext);
}

#[test]
fn crypto_roundtrip_wrong_key_fails() {
    let salt = [3u8; 16];
    let params = KdfParams::for_test();

    let correct_key =
        derive_root_key("pw1", &salt, &params).expect("derive correct key");
    let wrong_key = derive_root_key("pw2", &salt, &params).expect("derive wrong key");

    let blob = encrypt_bytes(&correct_key, b"secret", b"aad").expect("encrypt");
    let result = decrypt_bytes(&wrong_key, &blob, b"aad");
    assert!(result.is_err());
}


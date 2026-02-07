use super::*;

#[test]
fn is_supported_document_mime_type_includes_text_and_office_types() {
    assert!(is_supported_document_mime_type("application/pdf"));
    assert!(is_supported_document_mime_type(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ));
    assert!(is_supported_document_mime_type("text/plain"));
    assert!(is_supported_document_mime_type("application/json"));
}

#[test]
fn is_supported_document_mime_type_excludes_binary_media_types() {
    assert!(!is_supported_document_mime_type("image/png"));
    assert!(!is_supported_document_mime_type("video/mp4"));
    assert!(!is_supported_document_mime_type("audio/mpeg"));
}

#[test]
fn url_manifest_mime_helper_matches_expected_type() {
    assert!(is_url_manifest_mime_type(
        "application/x.secondloop.url+json"
    ));
    assert!(!is_url_manifest_mime_type("application/json"));
}

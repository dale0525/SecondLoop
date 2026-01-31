use secondloop_rust::embedding::brok_embeddings_url;

#[test]
fn brok_embeddings_url_appends_embeddings_path() {
    assert_eq!(
        brok_embeddings_url("https://example.com/v1"),
        "https://example.com/v1/embeddings"
    );
    assert_eq!(
        brok_embeddings_url("https://example.com/v1/"),
        "https://example.com/v1/embeddings"
    );
}

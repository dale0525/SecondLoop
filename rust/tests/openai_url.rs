use secondloop_rust::llm::openai;

#[test]
fn openai_chat_completions_url_is_joined_safely() {
    assert_eq!(
        openai::chat_completions_url("https://api.openai.com/v1"),
        "https://api.openai.com/v1/chat/completions"
    );
    assert_eq!(
        openai::chat_completions_url("https://api.openai.com/v1/"),
        "https://api.openai.com/v1/chat/completions"
    );
    assert_eq!(
        openai::chat_completions_url("https://example.com"),
        "https://example.com/chat/completions"
    );
}

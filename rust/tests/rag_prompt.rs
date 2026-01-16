use secondloop_rust::rag;

#[test]
fn rag_prompt_includes_context_and_question() {
    let prompt = rag::build_prompt(
        "How should I plan my day?",
        &["Buy milk".to_string(), "Meet Alice at 3pm".to_string()],
    );

    assert!(prompt.contains("Buy milk"));
    assert!(prompt.contains("Meet Alice at 3pm"));
    assert!(prompt.contains("How should I plan my day?"));
}

use secondloop_rust::db::LlmProfileConfig;
use secondloop_rust::llm;

#[test]
fn provider_from_profile_requires_api_key_for_openai_compatible() {
    let config = LlmProfileConfig {
        provider_type: "openai-compatible".to_string(),
        base_url: None,
        api_key: None,
        model_name: "gpt-4o-mini".to_string(),
    };

    let err = match llm::answer_provider_from_profile(&config) {
        Ok(_) => panic!("should error"),
        Err(e) => e,
    };
    assert!(err
        .to_string()
        .contains("missing api_key for openai-compatible provider"));
}

#[test]
fn provider_from_profile_rejects_non_openai_compatible_provider_types() {
    for provider_type in ["gemini-compatible", "anthropic-compatible"] {
        let config = LlmProfileConfig {
            provider_type: provider_type.to_string(),
            base_url: Some("https://example.com/v1".to_string()),
            api_key: Some("test-key".to_string()),
            model_name: "test-model".to_string(),
        };

        let err = match llm::answer_provider_from_profile(&config) {
            Ok(_) => panic!("should reject {provider_type}"),
            Err(e) => e,
        };
        let expected_message = format!("unsupported provider_type: {provider_type}");
        assert!(
            err.to_string().contains(&expected_message),
            "unexpected error for {provider_type}: {err}"
        );
    }
}

#[test]
fn provider_from_profile_rejects_unknown_provider_type() {
    let config = LlmProfileConfig {
        provider_type: "unknown".to_string(),
        base_url: None,
        api_key: None,
        model_name: "x".to_string(),
    };

    let err = match llm::answer_provider_from_profile(&config) {
        Ok(_) => panic!("should error"),
        Err(e) => e,
    };
    assert!(err
        .to_string()
        .contains("unsupported provider_type: unknown"));
}

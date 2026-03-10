use crate::knowledge::{normalize_retrieval_request, KnowledgeQueryScope, KnowledgeSourceKind};

#[test]
fn knowledge_retrieval_query_parses_language_scope_source_and_time_hints() {
    let request = normalize_retrieval_request(
        "lang:en scope:conversation source:transcript,metadata from:10 to:20 budget freeze",
        Some("conv-1".to_string()),
        None,
        None,
        None,
        None,
    );

    assert_eq!(request.query_text, "budget freeze");
    assert_eq!(request.language_hint.as_deref(), Some("en"));
    assert_eq!(request.scope, KnowledgeQueryScope::Conversation);
    assert_eq!(request.conversation_id.as_deref(), Some("conv-1"));
    assert_eq!(request.time_start_ms, Some(10));
    assert_eq!(request.time_end_ms, Some(20));
    assert_eq!(
        request.source_filters,
        vec![
            KnowledgeSourceKind::Transcript,
            KnowledgeSourceKind::Metadata
        ]
    );
}

#[test]
fn knowledge_retrieval_query_applies_default_limits() {
    let request = normalize_retrieval_request("roadmap", None, None, None, None, None);

    assert_eq!(request.scope, KnowledgeQueryScope::All);
    assert_eq!(request.query_text, "roadmap");
    assert_eq!(request.normalized_query, "roadmap");
    assert!(request.top_k >= 4);
    assert!(request.candidate_limit >= request.top_k);
    assert!(request.token_budget >= 256);
}

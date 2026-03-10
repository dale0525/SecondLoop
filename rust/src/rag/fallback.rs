pub(crate) fn should_use_legacy_retrieval_fallback(contexts: &[String]) -> bool {
    const MIN_KNOWLEDGE_CONTEXTS_TO_SKIP_LEGACY: usize = 2;

    let non_empty_count = contexts.iter().filter(|ctx| !ctx.trim().is_empty()).count();
    non_empty_count < MIN_KNOWLEDGE_CONTEXTS_TO_SKIP_LEGACY
}

#[cfg(test)]
mod tests {
    use super::should_use_legacy_retrieval_fallback;

    #[test]
    fn knowledge_fallback_uses_legacy_when_knowledge_contexts_are_empty() {
        assert!(should_use_legacy_retrieval_fallback(&[]));
    }

    #[test]
    fn knowledge_fallback_skips_legacy_when_knowledge_contexts_exist() {
        assert!(!should_use_legacy_retrieval_fallback(&[
            "context block 1".to_string(),
            "context block 2".to_string(),
        ]));
    }

    #[test]
    fn knowledge_fallback_uses_legacy_when_only_one_knowledge_context_exists() {
        assert!(should_use_legacy_retrieval_fallback(&[
            "context block".to_string()
        ]));
    }
}

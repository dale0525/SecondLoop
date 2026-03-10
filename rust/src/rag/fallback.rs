pub(crate) fn should_use_legacy_retrieval_fallback(contexts: &[String]) -> bool {
    contexts.is_empty()
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
            "context block".to_string()
        ]));
    }
}

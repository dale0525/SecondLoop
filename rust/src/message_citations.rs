pub(crate) fn message_citation_link(message_id: &str) -> Option<String> {
    let trimmed = message_id.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(format!("[History](secondloop://message/{trimmed})"))
}

pub(crate) fn append_message_citation_if_missing(mut context: String, message_id: &str) -> String {
    let Some(citation) = message_citation_link(message_id) else {
        return context;
    };
    if context.contains(&citation) {
        return context;
    }
    if !context.is_empty() && !context.ends_with('\n') {
        context.push('\n');
    }
    context.push_str(&citation);
    context
}

#[cfg(test)]
mod tests {
    use super::{append_message_citation_if_missing, message_citation_link};

    #[test]
    fn message_citation_link_trims_message_id() {
        assert_eq!(
            message_citation_link("  abc  "),
            Some("[History](secondloop://message/abc)".to_string())
        );
        assert_eq!(message_citation_link("   "), None);
    }

    #[test]
    fn append_message_citation_avoids_leading_or_double_newlines() {
        let empty = append_message_citation_if_missing(String::new(), "abc");
        assert_eq!(empty, "[History](secondloop://message/abc)");

        let single = append_message_citation_if_missing("body".to_string(), "abc");
        assert_eq!(single, "body\n[History](secondloop://message/abc)");

        let trailing_newline = append_message_citation_if_missing("body\n".to_string(), "abc");
        assert_eq!(
            trailing_newline,
            "body\n[History](secondloop://message/abc)"
        );
    }
}

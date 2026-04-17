use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnswerEvidenceDirectSource {
    pub id: String,
    pub href: String,
    pub source_type: String,
    pub label: String,
    pub source_type_label: Option<String>,
    pub scope_label: Option<String>,
    pub confidence_label: Option<String>,
    pub title: Option<String>,
    pub snippet: String,
    pub highlighted_text: Option<String>,
    pub created_at_ms: Option<i64>,
    pub updated_at_ms: Option<i64>,
    pub document_id: Option<String>,
    pub unit_id: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnswerEvidencePayload {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub direct_sources: Vec<AnswerEvidenceDirectSource>,
}

pub(crate) fn message_citation_href(message_id: &str) -> Option<String> {
    let trimmed = message_id.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(format!("secondloop://message/{trimmed}"))
}

pub(crate) fn message_citation_link(message_id: &str) -> Option<String> {
    message_citation_href(message_id).map(|href| format!("[History]({href})"))
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

pub(crate) fn encode_answer_evidence_json(
    direct_sources: Vec<AnswerEvidenceDirectSource>,
) -> Option<String> {
    if direct_sources.is_empty() {
        return None;
    }

    let payload = AnswerEvidencePayload {
        direct_sources: dedupe_direct_sources(direct_sources),
    };
    serde_json::to_string(&payload).ok()
}

fn dedupe_direct_sources(
    direct_sources: Vec<AnswerEvidenceDirectSource>,
) -> Vec<AnswerEvidenceDirectSource> {
    let mut seen = std::collections::HashSet::<String>::new();
    let mut out = Vec::<AnswerEvidenceDirectSource>::new();
    for item in direct_sources {
        let key = format!(
            "{}|{}",
            item.href,
            item.unit_id.as_deref().unwrap_or_default()
        );
        if !seen.insert(key) {
            continue;
        }
        out.push(item);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{
        append_message_citation_if_missing, encode_answer_evidence_json, message_citation_href,
        message_citation_link, AnswerEvidenceDirectSource,
    };

    #[test]
    fn message_citation_link_trims_message_id() {
        assert_eq!(
            message_citation_link("  abc  "),
            Some("[History](secondloop://message/abc)".to_string())
        );
        assert_eq!(
            message_citation_href("  abc  "),
            Some("secondloop://message/abc".to_string())
        );
        assert_eq!(message_citation_link("   "), None);
        assert_eq!(message_citation_href("   "), None);
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

    #[test]
    fn encode_answer_evidence_json_dedupes_items() {
        let direct = AnswerEvidenceDirectSource {
            id: "message:abc".to_string(),
            href: "secondloop://message/abc".to_string(),
            source_type: "message".to_string(),
            label: "History".to_string(),
            source_type_label: Some("chat_message".to_string()),
            scope_label: Some("this_thread".to_string()),
            confidence_label: Some("high_relevance".to_string()),
            title: None,
            snippet: "hello".to_string(),
            highlighted_text: Some("hello".to_string()),
            created_at_ms: Some(1),
            updated_at_ms: Some(1),
            document_id: None,
            unit_id: None,
        };

        let raw = encode_answer_evidence_json(vec![direct.clone(), direct]).expect("json");
        let parsed: serde_json::Value = serde_json::from_str(&raw).expect("valid json");
        assert_eq!(parsed["direct_sources"].as_array().map(Vec::len), Some(1));
    }

    #[test]
    fn encode_answer_evidence_json_omits_empty_payloads() {
        assert!(encode_answer_evidence_json(Vec::new()).is_none());
    }
}

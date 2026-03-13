use std::collections::BTreeSet;

use crate::knowledge::models::GeneratedMemoryKind;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemoryMergePolicy {
    AppendOnly,
    ReplaceLatest,
    MergeByFacet,
}

pub fn merge_policy(kind: GeneratedMemoryKind) -> MemoryMergePolicy {
    match kind {
        GeneratedMemoryKind::Profile => MemoryMergePolicy::ReplaceLatest,
        GeneratedMemoryKind::Preference => MemoryMergePolicy::MergeByFacet,
        GeneratedMemoryKind::Pattern => MemoryMergePolicy::MergeByFacet,
        GeneratedMemoryKind::Event => MemoryMergePolicy::AppendOnly,
    }
}

pub fn merge_lines(existing: &str, incoming: &str) -> String {
    let mut seen = BTreeSet::<String>::new();
    let mut out = Vec::<String>::new();
    for line in existing.lines().chain(incoming.lines()) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if seen.insert(trimmed.to_string()) {
            out.push(trimmed.to_string());
        }
    }
    out.join("\n")
}

pub fn build_generated_document_id(
    kind: GeneratedMemoryKind,
    facet_key: &str,
    source_id: Option<&str>,
) -> String {
    match merge_policy(kind) {
        MemoryMergePolicy::AppendOnly => format!(
            "generated:{}:{}:{}",
            kind.as_str(),
            sanitize_key(facet_key),
            sanitize_key(source_id.unwrap_or("item"))
        ),
        MemoryMergePolicy::ReplaceLatest | MemoryMergePolicy::MergeByFacet => {
            format!("generated:{}:{}", kind.as_str(), sanitize_key(facet_key))
        }
    }
}

fn sanitize_key(value: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;
    for ch in value.chars() {
        let normalized = if ch.is_ascii_alphanumeric() {
            ch.to_ascii_lowercase()
        } else {
            '-'
        };
        if normalized == '-' {
            if !last_dash {
                out.push('-');
            }
            last_dash = true;
        } else {
            out.push(normalized);
            last_dash = false;
        }
    }
    out.trim_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::{build_generated_document_id, merge_lines, merge_policy, MemoryMergePolicy};
    use crate::knowledge::models::GeneratedMemoryKind;

    #[test]
    fn generated_preferences_merge_by_facet_key() {
        let left =
            build_generated_document_id(GeneratedMemoryKind::Preference, "response_style", None);
        let right = build_generated_document_id(
            GeneratedMemoryKind::Preference,
            "response_style",
            Some("msg-1"),
        );
        assert_eq!(left, right);
        assert_eq!(
            merge_policy(GeneratedMemoryKind::Preference),
            MemoryMergePolicy::MergeByFacet
        );
    }

    #[test]
    fn merge_lines_deduplicates_repeated_entries() {
        let merged = merge_lines("- concise\n- chinese", "- chinese\n- bullets");
        assert_eq!(merged, "- concise\n- chinese\n- bullets");
    }
}

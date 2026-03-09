use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeRole, KnowledgeSourceKind,
};

#[derive(Clone, Debug, PartialEq)]
pub struct SegmentDraft {
    pub ordinal: i64,
    pub raw_text: String,
    pub normalized_text: String,
    pub role: KnowledgeRole,
    pub anchors: KnowledgeAnchorSet,
}

fn split_paragraphs(text: &str) -> Vec<&str> {
    text.trim()
        .split("\n\n")
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .collect()
}

pub fn segment_document_text(document: &ContentKnowledgeDocument) -> Vec<SegmentDraft> {
    let normalized_chunks = split_paragraphs(&document.normalized_text);
    if normalized_chunks.is_empty() {
        return Vec::new();
    }
    let raw_chunks = split_paragraphs(&document.raw_text);

    let mut out = Vec::<SegmentDraft>::new();
    for (index, chunk) in normalized_chunks.iter().enumerate() {
        let mut anchors = document.anchors.clone();
        if document.source_kind == KnowledgeSourceKind::Transcript {
            let label = chunk
                .lines()
                .next()
                .unwrap_or_default()
                .split(':')
                .next()
                .unwrap_or_default()
                .trim();
            if !label.is_empty() {
                anchors.section_label = Some(label.to_string());
            }
        }
        out.push(SegmentDraft {
            ordinal: index as i64,
            raw_text: raw_chunks
                .get(index)
                .copied()
                .unwrap_or_default()
                .to_string(),
            normalized_text: (*chunk).to_string(),
            role: document.role,
            anchors,
        });
    }
    out
}

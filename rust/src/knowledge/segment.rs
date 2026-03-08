use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeRole, KnowledgeSourceKind,
};

#[derive(Clone, Debug, PartialEq)]
pub struct SegmentDraft {
    pub ordinal: i64,
    pub text: String,
    pub role: KnowledgeRole,
    pub anchors: KnowledgeAnchorSet,
}

pub fn segment_document_text(document: &ContentKnowledgeDocument) -> Vec<SegmentDraft> {
    let source = document.normalized_text.trim();
    if source.is_empty() {
        return Vec::new();
    }

    let chunks = source
        .split("\n\n")
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();

    let mut out = Vec::<SegmentDraft>::new();
    for (index, chunk) in chunks.iter().enumerate() {
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
            text: (*chunk).to_string(),
            role: document.role,
            anchors,
        });
    }
    out
}

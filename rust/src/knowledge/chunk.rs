use std::time::{SystemTime, UNIX_EPOCH};

use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeUnit, KnowledgeUnitKind, SegmentDraft,
};

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn estimate_token_count(text: &str) -> usize {
    text.split_whitespace().count().max(1)
}

fn split_segment_to_fit(text: &str, max_tokens: usize) -> Vec<String> {
    let words = text.split_whitespace().collect::<Vec<_>>();
    if words.is_empty() {
        return Vec::new();
    }
    if words.len() <= max_tokens.max(1) {
        return vec![words.join(" ")];
    }

    let mut out = Vec::<String>::new();
    let mut start = 0usize;
    let step = max_tokens.max(1);
    while start < words.len() {
        let end = (start + step).min(words.len());
        out.push(words[start..end].join(" "));
        start = end;
    }
    out
}

pub fn build_section_units(
    document: &ContentKnowledgeDocument,
    segments: &[SegmentDraft],
) -> Vec<KnowledgeUnit> {
    let created_at_ms = now_ms();
    segments
        .iter()
        .enumerate()
        .map(|(index, segment)| KnowledgeUnit {
            unit_id: format!("{}:section:{index:04}", document.document_id),
            document_id: document.document_id.clone(),
            parent_unit_id: None,
            unit_kind: KnowledgeUnitKind::Section,
            source_kind: document.source_kind,
            role: segment.role,
            ordinal: index as i64,
            token_count: estimate_token_count(&segment.text) as i64,
            raw_text: segment.text.clone(),
            normalized_text: segment.text.clone(),
            anchors: segment.anchors.clone(),
            prev_unit_id: None,
            next_unit_id: None,
            created_at_ms,
            updated_at_ms: created_at_ms,
        })
        .collect()
}

pub fn build_segment_units(
    document: &ContentKnowledgeDocument,
    segments: &[SegmentDraft],
) -> Vec<KnowledgeUnit> {
    let created_at_ms = now_ms();
    segments
        .iter()
        .enumerate()
        .map(|(index, segment)| KnowledgeUnit {
            unit_id: format!("{}:segment:{index:04}", document.document_id),
            document_id: document.document_id.clone(),
            parent_unit_id: None,
            unit_kind: KnowledgeUnitKind::Segment,
            source_kind: document.source_kind,
            role: segment.role,
            ordinal: index as i64,
            token_count: estimate_token_count(&segment.text) as i64,
            raw_text: segment.text.clone(),
            normalized_text: segment.text.clone(),
            anchors: segment.anchors.clone(),
            prev_unit_id: None,
            next_unit_id: None,
            created_at_ms,
            updated_at_ms: created_at_ms,
        })
        .collect()
}

pub fn build_chunk_units(
    document: &ContentKnowledgeDocument,
    segments: &[SegmentDraft],
    target_tokens: usize,
    max_tokens: usize,
) -> Vec<KnowledgeUnit> {
    let created_at_ms = now_ms();
    let mut raw_parts = Vec::<(String, SegmentDraft)>::new();
    for segment in segments {
        for part in split_segment_to_fit(&segment.text, max_tokens.max(1)) {
            raw_parts.push((part, segment.clone()));
        }
    }

    let mut chunks = Vec::<KnowledgeUnit>::new();
    let mut buffer = Vec::<String>::new();
    let mut buffer_tokens = 0usize;
    let mut ordinal = 0i64;
    let mut current_anchor = document.anchors.clone();
    let target_tokens = target_tokens.max(1);
    let max_tokens = max_tokens.max(target_tokens);

    let flush = |chunks: &mut Vec<KnowledgeUnit>,
                 buffer: &mut Vec<String>,
                 buffer_tokens: &mut usize,
                 current_anchor: &KnowledgeAnchorSet,
                 ordinal: &mut i64| {
        if buffer.is_empty() {
            return;
        }
        let text = buffer.join("\n\n");
        chunks.push(KnowledgeUnit {
            unit_id: format!("{}:chunk:{:04}", document.document_id, *ordinal),
            document_id: document.document_id.clone(),
            parent_unit_id: None,
            unit_kind: KnowledgeUnitKind::Chunk,
            source_kind: document.source_kind,
            role: document.role,
            ordinal: *ordinal,
            token_count: *buffer_tokens as i64,
            raw_text: text.clone(),
            normalized_text: text,
            anchors: current_anchor.clone(),
            prev_unit_id: None,
            next_unit_id: None,
            created_at_ms,
            updated_at_ms: created_at_ms,
        });
        *ordinal += 1;
        buffer.clear();
        *buffer_tokens = 0;
    };

    for (part, segment) in raw_parts {
        let part_tokens = estimate_token_count(&part);
        if buffer_tokens.saturating_add(part_tokens) > max_tokens && !buffer.is_empty() {
            flush(
                &mut chunks,
                &mut buffer,
                &mut buffer_tokens,
                &current_anchor,
                &mut ordinal,
            );
        }
        if buffer.is_empty() {
            current_anchor = segment.anchors.clone();
        }
        buffer.push(part);
        buffer_tokens += part_tokens;
        if buffer_tokens >= target_tokens {
            flush(
                &mut chunks,
                &mut buffer,
                &mut buffer_tokens,
                &current_anchor,
                &mut ordinal,
            );
        }
    }
    flush(
        &mut chunks,
        &mut buffer,
        &mut buffer_tokens,
        &current_anchor,
        &mut ordinal,
    );

    let ids = chunks
        .iter()
        .map(|value| value.unit_id.clone())
        .collect::<Vec<_>>();
    for (index, chunk) in chunks.iter_mut().enumerate() {
        chunk.prev_unit_id = index
            .checked_sub(1)
            .and_then(|value| ids.get(value).cloned());
        chunk.next_unit_id = ids.get(index + 1).cloned();
    }

    chunks
}

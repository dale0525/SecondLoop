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

fn split_text_to_fit(text: &str, max_tokens: usize) -> Vec<String> {
    let mut token_ranges = Vec::<(usize, usize)>::new();
    let mut token_start = None;

    for (index, ch) in text.char_indices() {
        if ch.is_whitespace() {
            if let Some(start) = token_start.take() {
                token_ranges.push((start, index));
            }
        } else if token_start.is_none() {
            token_start = Some(index);
        }
    }

    if let Some(start) = token_start {
        token_ranges.push((start, text.len()));
    }

    if token_ranges.is_empty() {
        return Vec::new();
    }

    token_ranges
        .chunks(max_tokens.max(1))
        .map(|chunk| {
            let start = chunk.first().map(|value| value.0).unwrap_or(0);
            let end = chunk.last().map(|value| value.1).unwrap_or(text.len());
            text[start..end].to_string()
        })
        .collect()
}

fn split_segment_to_fit(
    raw_text: &str,
    normalized_text: &str,
    max_tokens: usize,
) -> Vec<(String, String)> {
    let normalized_words = normalized_text.split_whitespace().count();
    if normalized_words <= max_tokens.max(1) {
        return vec![(raw_text.to_string(), normalized_text.to_string())];
    }

    let raw_parts = split_text_to_fit(raw_text, max_tokens);
    let normalized_parts = split_text_to_fit(normalized_text, max_tokens);
    let count = raw_parts.len().max(normalized_parts.len());
    let mut out = Vec::<(String, String)>::with_capacity(count);
    for index in 0..count {
        let raw_part = raw_parts.get(index).cloned().unwrap_or_default();
        let normalized_part = normalized_parts.get(index).cloned().unwrap_or_default();
        out.push((raw_part, normalized_part));
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
            token_count: estimate_token_count(&segment.normalized_text) as i64,
            raw_text: segment.raw_text.clone(),
            normalized_text: segment.normalized_text.clone(),
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
            token_count: estimate_token_count(&segment.normalized_text) as i64,
            raw_text: segment.raw_text.clone(),
            normalized_text: segment.normalized_text.clone(),
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
    let target_tokens = target_tokens.max(1);
    let max_tokens = max_tokens.max(target_tokens);
    let mut parts = Vec::<(String, String, KnowledgeAnchorSet)>::new();
    for segment in segments {
        for (raw_part, normalized_part) in
            split_segment_to_fit(&segment.raw_text, &segment.normalized_text, max_tokens)
        {
            parts.push((raw_part, normalized_part, segment.anchors.clone()));
        }
    }

    let mut chunks = Vec::<KnowledgeUnit>::new();
    let mut raw_buffer = Vec::<String>::new();
    let mut normalized_buffer = Vec::<String>::new();
    let mut buffer_tokens = 0usize;
    let mut ordinal = 0i64;
    let mut current_anchor = document.anchors.clone();

    let flush = |chunks: &mut Vec<KnowledgeUnit>,
                 raw_buffer: &mut Vec<String>,
                 normalized_buffer: &mut Vec<String>,
                 buffer_tokens: &mut usize,
                 current_anchor: &KnowledgeAnchorSet,
                 ordinal: &mut i64| {
        if normalized_buffer.is_empty() {
            return;
        }
        let raw_text = raw_buffer.join("\n\n");
        let normalized_text = normalized_buffer.join("\n\n");
        chunks.push(KnowledgeUnit {
            unit_id: format!("{}:chunk:{:04}", document.document_id, *ordinal),
            document_id: document.document_id.clone(),
            parent_unit_id: None,
            unit_kind: KnowledgeUnitKind::Chunk,
            source_kind: document.source_kind,
            role: document.role,
            ordinal: *ordinal,
            token_count: *buffer_tokens as i64,
            raw_text,
            normalized_text,
            anchors: current_anchor.clone(),
            prev_unit_id: None,
            next_unit_id: None,
            created_at_ms,
            updated_at_ms: created_at_ms,
        });
        *ordinal += 1;
        raw_buffer.clear();
        normalized_buffer.clear();
        *buffer_tokens = 0;
    };

    for (raw_part, normalized_part, anchors) in parts {
        let part_tokens = estimate_token_count(&normalized_part);
        if buffer_tokens.saturating_add(part_tokens) > max_tokens && !normalized_buffer.is_empty() {
            flush(
                &mut chunks,
                &mut raw_buffer,
                &mut normalized_buffer,
                &mut buffer_tokens,
                &current_anchor,
                &mut ordinal,
            );
        }
        if normalized_buffer.is_empty() {
            current_anchor = anchors;
        }
        raw_buffer.push(raw_part);
        normalized_buffer.push(normalized_part);
        buffer_tokens += part_tokens;
        if buffer_tokens >= target_tokens {
            flush(
                &mut chunks,
                &mut raw_buffer,
                &mut normalized_buffer,
                &mut buffer_tokens,
                &current_anchor,
                &mut ordinal,
            );
        }
    }
    flush(
        &mut chunks,
        &mut raw_buffer,
        &mut normalized_buffer,
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

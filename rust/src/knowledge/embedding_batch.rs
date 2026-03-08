#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EmbeddingBatchPolicy {
    pub max_inputs_per_batch: usize,
    pub max_tokens_per_batch: usize,
    pub max_bytes_per_batch: usize,
    pub max_tokens_per_input: usize,
    pub max_bytes_per_input: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreparedEmbeddingInput {
    pub source_index: usize,
    pub text: String,
}

impl Default for EmbeddingBatchPolicy {
    fn default() -> Self {
        Self {
            max_inputs_per_batch: 16,
            max_tokens_per_batch: 4096,
            max_bytes_per_batch: 64 * 1024,
            max_tokens_per_input: 512,
            max_bytes_per_input: 8 * 1024,
        }
    }
}

pub fn estimate_tokens(text: &str) -> usize {
    text.split_whitespace().count().max(1)
}

pub fn split_oversized_embedding_input(text: &str, policy: EmbeddingBatchPolicy) -> Vec<String> {
    let words = text.split_whitespace().collect::<Vec<_>>();
    if words.is_empty() {
        return Vec::new();
    }
    let max_tokens = policy.max_tokens_per_input.max(1);
    let max_bytes = policy.max_bytes_per_input.max(1);
    let mut out = Vec::<String>::new();
    let mut current = Vec::<&str>::new();
    let mut current_bytes = 0usize;

    for word in words {
        let candidate_bytes = current_bytes + word.len() + usize::from(!current.is_empty());
        if (current.len() >= max_tokens || candidate_bytes > max_bytes) && !current.is_empty() {
            out.push(current.join(" "));
            current.clear();
            current_bytes = 0;
        }
        current_bytes += word.len() + usize::from(!current.is_empty());
        current.push(word);
    }

    if !current.is_empty() {
        out.push(current.join(" "));
    }
    out
}

pub fn normalize_inputs_for_embedding(
    texts: &[String],
    policy: EmbeddingBatchPolicy,
) -> Vec<String> {
    let mut out = Vec::<String>::new();
    for text in texts {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let tokens = estimate_tokens(trimmed);
        let bytes = trimmed.len();
        if tokens > policy.max_tokens_per_input || bytes > policy.max_bytes_per_input {
            out.extend(split_oversized_embedding_input(trimmed, policy));
        } else {
            out.push(trimmed.to_string());
        }
    }
    out
}

pub fn prepare_embedding_inputs(
    texts: &[String],
    policy: EmbeddingBatchPolicy,
) -> Vec<PreparedEmbeddingInput> {
    let mut out = Vec::<PreparedEmbeddingInput>::new();
    for (source_index, text) in texts.iter().enumerate() {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let tokens = estimate_tokens(trimmed);
        let bytes = trimmed.len();
        if tokens > policy.max_tokens_per_input || bytes > policy.max_bytes_per_input {
            for piece in split_oversized_embedding_input(trimmed, policy) {
                out.push(PreparedEmbeddingInput {
                    source_index,
                    text: piece,
                });
            }
        } else {
            out.push(PreparedEmbeddingInput {
                source_index,
                text: trimmed.to_string(),
            });
        }
    }
    out
}

pub fn batch_prepared_embedding_inputs(
    inputs: &[PreparedEmbeddingInput],
    policy: EmbeddingBatchPolicy,
) -> Vec<Vec<PreparedEmbeddingInput>> {
    if inputs.is_empty() {
        return Vec::new();
    }

    let mut batches = Vec::<Vec<PreparedEmbeddingInput>>::new();
    let mut current = Vec::<PreparedEmbeddingInput>::new();
    let mut current_tokens = 0usize;
    let mut current_bytes = 0usize;

    for input in inputs {
        let text_tokens = estimate_tokens(&input.text);
        let text_bytes = input.text.len();
        let too_many_inputs = current.len() >= policy.max_inputs_per_batch.max(1);
        let too_many_tokens =
            current_tokens.saturating_add(text_tokens) > policy.max_tokens_per_batch.max(1);
        let too_many_bytes =
            current_bytes.saturating_add(text_bytes) > policy.max_bytes_per_batch.max(1);
        if (too_many_inputs || too_many_tokens || too_many_bytes) && !current.is_empty() {
            batches.push(std::mem::take(&mut current));
            current_tokens = 0;
            current_bytes = 0;
        }

        current_tokens += text_tokens;
        current_bytes += text_bytes;
        current.push(input.clone());
    }

    if !current.is_empty() {
        batches.push(current);
    }
    batches
}

pub fn average_piece_embeddings(
    piece_embeddings: Vec<Vec<Vec<f32>>>,
    expected_len: usize,
) -> Vec<Vec<f32>> {
    let mut out = Vec::<Vec<f32>>::with_capacity(expected_len);
    for pieces in piece_embeddings {
        if pieces.is_empty() {
            out.push(Vec::new());
            continue;
        }
        if pieces.len() == 1 {
            out.push(pieces.into_iter().next().unwrap_or_default());
            continue;
        }
        let dim = pieces[0].len();
        let mut merged = vec![0f32; dim];
        let piece_count = pieces.len() as f32;
        for piece in pieces {
            for (index, value) in piece.into_iter().enumerate() {
                if index < merged.len() {
                    merged[index] += value;
                }
            }
        }
        for value in &mut merged {
            *value /= piece_count;
        }
        out.push(merged);
    }
    if out.len() < expected_len {
        out.resize_with(expected_len, Vec::new);
    }
    out
}

pub fn batch_embedding_inputs(texts: &[String], policy: EmbeddingBatchPolicy) -> Vec<Vec<String>> {
    let normalized = normalize_inputs_for_embedding(texts, policy);
    if normalized.is_empty() {
        return Vec::new();
    }

    let mut batches = Vec::<Vec<String>>::new();
    let mut current = Vec::<String>::new();
    let mut current_tokens = 0usize;
    let mut current_bytes = 0usize;

    for text in normalized {
        let text_tokens = estimate_tokens(&text);
        let text_bytes = text.len();
        let too_many_inputs = current.len() >= policy.max_inputs_per_batch.max(1);
        let too_many_tokens =
            current_tokens.saturating_add(text_tokens) > policy.max_tokens_per_batch.max(1);
        let too_many_bytes =
            current_bytes.saturating_add(text_bytes) > policy.max_bytes_per_batch.max(1);
        if (too_many_inputs || too_many_tokens || too_many_bytes) && !current.is_empty() {
            batches.push(std::mem::take(&mut current));
            current_tokens = 0;
            current_bytes = 0;
        }
        current_tokens += text_tokens;
        current_bytes += text_bytes;
        current.push(text);
    }
    if !current.is_empty() {
        batches.push(current);
    }
    batches
}

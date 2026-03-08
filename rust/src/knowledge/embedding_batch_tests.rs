use crate::knowledge::embedding_batch::{
    batch_embedding_inputs, split_oversized_embedding_input, EmbeddingBatchPolicy,
};

#[test]
fn knowledge_embedding_batch_splits_oversized_input_by_policy_caps() {
    let oversized = "alpha ".repeat(220);
    let pieces = split_oversized_embedding_input(
        &oversized,
        EmbeddingBatchPolicy {
            max_inputs_per_batch: 8,
            max_tokens_per_batch: 128,
            max_bytes_per_batch: 4096,
            max_tokens_per_input: 64,
            max_bytes_per_input: 1024,
        },
    );

    assert!(pieces.len() >= 2);
    assert!(pieces.iter().all(|piece| !piece.trim().is_empty()));
}

#[test]
fn knowledge_embedding_batch_groups_inputs_without_exceeding_caps() {
    let inputs = vec![
        "one two three".to_string(),
        "four five six".to_string(),
        "seven eight nine ten eleven twelve".to_string(),
        "thirteen fourteen fifteen sixteen seventeen eighteen".to_string(),
    ];

    let batches = batch_embedding_inputs(
        &inputs,
        EmbeddingBatchPolicy {
            max_inputs_per_batch: 2,
            max_tokens_per_batch: 8,
            max_bytes_per_batch: 64,
            max_tokens_per_input: 8,
            max_bytes_per_input: 64,
        },
    );

    assert!(batches.len() >= 2);
    assert!(batches.iter().all(|batch| batch.len() <= 2));
}

use crate::embedding::batch::{
    average_piece_embeddings, batch_embedding_inputs, ensure_non_empty_embedding_results,
    split_oversized_embedding_input, EmbeddingBatchPolicy,
};

#[test]
fn embedding_batch_splits_oversized_input_by_policy_caps() {
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
fn embedding_batch_groups_inputs_without_exceeding_caps() {
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

#[test]
fn embedding_batch_renormalizes_averaged_piece_embeddings() {
    let averaged = average_piece_embeddings(vec![vec![vec![1.0, 0.0], vec![0.0, 1.0]]], 1);

    assert_eq!(averaged.len(), 1);
    let embedding = &averaged[0];
    let norm = embedding
        .iter()
        .map(|value| value * value)
        .sum::<f32>()
        .sqrt();
    assert!(
        (norm - 1.0).abs() < 1e-6,
        "expected unit-length embedding, got norm {norm}"
    );
    assert!((embedding[0] - embedding[1]).abs() < 1e-6);
}

#[test]
fn embedding_batch_rejects_empty_embeddings() {
    let err = ensure_non_empty_embedding_results(&[vec![1.0, 0.0], Vec::new()])
        .expect_err("empty embedding slots should be rejected");
    assert!(err
        .to_string()
        .contains("embedding returned empty vector for one or more inputs"));
}

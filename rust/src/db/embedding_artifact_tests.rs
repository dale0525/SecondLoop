use tempfile::tempdir;

use super::*;

#[test]
fn embedding_artifact_identity_prefers_higher_priority_producer() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let mobile = record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "chunk-a",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("ios-device"),
            producer_class: "mobile",
            quality_tier: "reduced",
            vector_format: "f16",
            dimension: 384,
            blob_ref: "blob/mobile-a",
            created_at_ms: Some(100),
        },
    )
    .expect("mobile");
    assert_eq!(mobile.status, "ready");

    let desktop = record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "chunk-a",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("mac-device"),
            producer_class: "desktop",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 384,
            blob_ref: "blob/desktop-a",
            created_at_ms: Some(200),
        },
    )
    .expect("desktop");

    let active = get_active_embedding_artifact_for_identity(
        &conn,
        "message",
        "message-1",
        1,
        "chunk-a",
        "profile-1",
    )
    .expect("active")
    .expect("some active");
    assert_eq!(active.artifact_id, desktop.artifact_id);
    assert_eq!(active.producer_class, "desktop");

    let manifests = list_embedding_artifact_manifests_for_identity(
        &conn,
        "message",
        "message-1",
        1,
        "chunk-a",
        "profile-1",
    )
    .expect("manifests");
    assert_eq!(manifests.len(), 2);
    assert_eq!(manifests[0].artifact_id, desktop.artifact_id);
    assert_eq!(manifests[0].status, "ready");
    assert_eq!(manifests[1].artifact_id, mobile.artifact_id);
    assert_eq!(manifests[1].status, "superseded");
}

#[test]
fn embedding_artifact_cache_lookup_reuses_best_ready_chunk_across_revisions() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "shared-chunk",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("phone"),
            producer_class: "mobile",
            quality_tier: "reduced",
            vector_format: "f16",
            dimension: 384,
            blob_ref: "blob/mobile-shared",
            created_at_ms: Some(100),
        },
    )
    .expect("mobile");

    let byok = record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 2,
            chunk_hash: "shared-chunk",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: None,
            producer_class: "byok",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 384,
            blob_ref: "blob/byok-shared",
            created_at_ms: Some(200),
        },
    )
    .expect("byok");

    let cache_hit = find_best_embedding_artifact_cache_hit(&conn, "shared-chunk", "profile-1")
        .expect("cache hit")
        .expect("some hit");
    assert_eq!(cache_hit.artifact_id, byok.artifact_id);
    assert_eq!(cache_hit.source_revision, 2);
    assert_eq!(cache_hit.producer_class, "byok");
}

#[test]
fn embedding_artifact_source_revision_queries_ignore_old_revision_results() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "old-chunk",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("mac-device"),
            producer_class: "desktop",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 384,
            blob_ref: "blob/old",
            created_at_ms: Some(100),
        },
    )
    .expect("old");

    let revision_two = record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 2,
            chunk_hash: "new-chunk",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("mac-device"),
            producer_class: "desktop",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 384,
            blob_ref: "blob/new",
            created_at_ms: Some(200),
        },
    )
    .expect("new");

    let current = list_active_embedding_artifacts_for_source_revision(
        &conn,
        "message",
        "message-1",
        2,
        "profile-1",
    )
    .expect("current");
    assert_eq!(current.len(), 1);
    assert_eq!(current[0].artifact_id, revision_two.artifact_id);
    assert_eq!(current[0].chunk_hash, "new-chunk");

    let old = list_active_embedding_artifacts_for_source_revision(
        &conn,
        "message",
        "message-1",
        1,
        "profile-1",
    )
    .expect("old");
    assert_eq!(old.len(), 1);
    assert_eq!(old[0].chunk_hash, "old-chunk");
}

fn message_updated_at(conn: &Connection, message_id: &str) -> i64 {
    conn.query_row(
        r#"SELECT updated_at FROM messages WHERE id = ?1"#,
        params![message_id],
        |row| row.get(0),
    )
    .expect("message updated_at")
}

#[test]
fn embedding_artifact_edit_back_to_old_content_reuses_existing_blob() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [19u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "alpha notes")
        .expect("insert message");

    let processed_a =
        process_pending_message_embeddings_default(&conn, &key, 10).expect("process a");
    assert_eq!(processed_a, 1);
    let revision_a = message_updated_at(&conn, &message.id);
    let profile_id =
        embedding_artifact_profile_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM);
    let chunk_hash_a = {
        let mut hasher = Sha256::new();
        hasher.update(
            build_message_embedding_plaintext(&conn, &key, &message.id, "alpha notes")
                .expect("plaintext a2")
                .as_bytes(),
        );
        {
            let digest = hasher.finalize();
            let mut out = String::with_capacity(digest.len() * 2);
            for byte in digest {
                use std::fmt::Write;
                let _ = write!(&mut out, "{byte:02x}");
            }
            out
        }
    };
    let manifest_a = get_active_embedding_artifact_for_identity(
        &conn,
        "message",
        &message.id,
        revision_a,
        &chunk_hash_a,
        &profile_id,
    )
    .expect("active a")
    .expect("manifest a");

    edit_message(&conn, &key, &message.id, "beta notes").expect("edit beta");
    let processed_b =
        process_pending_message_embeddings_default(&conn, &key, 10).expect("process b");
    assert_eq!(processed_b, 1);

    edit_message(&conn, &key, &message.id, "alpha notes").expect("edit alpha again");
    let processed_c =
        process_pending_message_embeddings_default(&conn, &key, 10).expect("process c");
    assert_eq!(processed_c, 1);
    let revision_c = message_updated_at(&conn, &message.id);
    let manifest_c = get_active_embedding_artifact_for_identity(
        &conn,
        "message",
        &message.id,
        revision_c,
        &chunk_hash_a,
        &profile_id,
    )
    .expect("active c")
    .expect("manifest c");

    assert_eq!(manifest_c.blob_ref, manifest_a.blob_ref);
    let blob_refs = list_distinct_embedding_artifact_blob_refs(&conn).expect("blob refs");
    assert_eq!(blob_refs.len(), 2);
}

fn message_chunk_hash(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    content: &str,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(
        build_message_embedding_plaintext(conn, key, message_id, content)
            .expect("plaintext")
            .as_bytes(),
    );
    {
        let digest = hasher.finalize();
        let mut out = String::with_capacity(digest.len() * 2);
        for byte in digest {
            use std::fmt::Write;
            let _ = write!(&mut out, "{byte:02x}");
        }
        out
    }
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn desktop_default_pipeline_supersedes_mobile_artifact_for_same_identity() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [23u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("insert message");
    let revision = message_updated_at(&conn, &message.id);
    let chunk_hash = message_chunk_hash(&conn, &key, &message.id, "apple pie");
    let profile_id =
        embedding_artifact_profile_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM);

    let mobile_blob_ref = "blob/mobile-lower-priority";
    let mobile_embedding = vec![42.0f32; DEFAULT_EMBEDDING_DIM];
    let mobile_blob = encode_f32_embedding_artifact_blob(&mobile_embedding);
    write_embedding_artifact_blob(dir.path(), &key, mobile_blob_ref, &mobile_blob)
        .expect("write mobile blob");

    let mobile = record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: &message.id,
            source_revision: revision,
            chunk_hash: &chunk_hash,
            chunk_ordinal: 0,
            profile_id: &profile_id,
            producer_device_id: Some("ios-device"),
            producer_class: "mobile",
            quality_tier: "reduced",
            vector_format: "f32",
            dimension: DEFAULT_EMBEDDING_DIM as i64,
            blob_ref: mobile_blob_ref,
            created_at_ms: Some(100),
        },
    )
    .expect("mobile manifest");
    assert_eq!(mobile.status, "ready");

    let processed = process_pending_message_embeddings_default(&conn, &key, 10)
        .expect("process desktop default");
    assert_eq!(processed, 1);

    let active = get_active_embedding_artifact_for_identity(
        &conn,
        "message",
        &message.id,
        revision,
        &chunk_hash,
        &profile_id,
    )
    .expect("active")
    .expect("some active");
    assert_eq!(active.producer_class, "desktop");
    assert_ne!(active.artifact_id, mobile.artifact_id);
    assert_ne!(active.blob_ref, mobile_blob_ref);

    let old = get_embedding_artifact_manifest_by_id(&conn, &mobile.artifact_id)
        .expect("reload mobile")
        .expect("mobile exists");
    assert_eq!(old.status, "superseded");
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn desktop_default_pipeline_does_not_clone_lower_priority_mobile_cache_hit() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [29u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "banana bread")
        .expect("insert message");
    let revision = message_updated_at(&conn, &message.id);
    let chunk_hash = message_chunk_hash(&conn, &key, &message.id, "banana bread");
    let profile_id =
        embedding_artifact_profile_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM);

    let shared_blob_ref = "blob/mobile-cache-hit";
    let shared_embedding = vec![7.0f32; DEFAULT_EMBEDDING_DIM];
    let shared_blob = encode_f32_embedding_artifact_blob(&shared_embedding);
    write_embedding_artifact_blob(dir.path(), &key, shared_blob_ref, &shared_blob)
        .expect("write shared blob");

    record_embedding_artifact_manifest(
        &conn,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "other-message",
            source_revision: revision - 1,
            chunk_hash: &chunk_hash,
            chunk_ordinal: 0,
            profile_id: &profile_id,
            producer_device_id: Some("iphone"),
            producer_class: "mobile",
            quality_tier: "reduced",
            vector_format: "f32",
            dimension: DEFAULT_EMBEDDING_DIM as i64,
            blob_ref: shared_blob_ref,
            created_at_ms: Some(100),
        },
    )
    .expect("cache source manifest");

    let processed = process_pending_message_embeddings_default(&conn, &key, 10)
        .expect("process desktop default");
    assert_eq!(processed, 1);

    let active = get_active_embedding_artifact_for_identity(
        &conn,
        "message",
        &message.id,
        revision,
        &chunk_hash,
        &profile_id,
    )
    .expect("active")
    .expect("some active");
    assert_eq!(active.producer_class, "desktop");
    assert_ne!(active.blob_ref, shared_blob_ref);
}

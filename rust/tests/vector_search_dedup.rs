use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::{Embedder, DEFAULT_EMBED_DIM};
use secondloop_rust::{auth, db};

#[derive(Clone, Debug, Default)]
struct TestEmbedder;

impl Embedder for TestEmbedder {
    fn model_name(&self) -> &str {
        "test-embedder"
    }

    fn dim(&self) -> usize {
        DEFAULT_EMBED_DIM
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let mut out = Vec::with_capacity(texts.len());
        for text in texts {
            let mut v = vec![0.0f32; DEFAULT_EMBED_DIM];
            let t = text.to_lowercase();
            if t.contains("apple") {
                v[0] += 1.0;
            }
            if t.contains("pie") {
                v[0] += 1.0;
            }
            out.push(v);
        }
        Ok(out)
    }
}

#[derive(Clone, Debug, Default)]
struct EmptyContentOrderingEmbedder;

impl Embedder for EmptyContentOrderingEmbedder {
    fn model_name(&self) -> &str {
        "test-empty-content-ordering-embedder"
    }

    fn dim(&self) -> usize {
        DEFAULT_EMBED_DIM
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let mut out = Vec::with_capacity(texts.len());
        for text in texts {
            let mut v = vec![1.0f32; DEFAULT_EMBED_DIM];
            if text.contains("query: 越夜越动听") || text.contains("UNRELATED_ALPHA") {
                v[0] = 0.0;
            } else if text.contains("TARGET_BETA") {
                v[0] = 0.2;
            }
            out.push(v);
        }
        Ok(out)
    }
}

#[test]
fn vector_search_dedupes_duplicate_message_contents() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let _m1 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m1");
    let _m2 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m2");
    let _m3 = db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m3");

    let embedder = TestEmbedder;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 100).expect("index");

    let results = db::search_similar_messages(&conn, &key, &embedder, "apple", 2).expect("search");
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].message.content, "apple");
    assert_eq!(results[1].message.content, "apple pie");
    assert!(results[0].distance <= results[1].distance);
}

#[test]
fn vector_search_keeps_distinct_audio_transcripts_when_message_content_is_empty() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message_1 = db::insert_message(&conn, &key, &conversation.id, "user", "").expect("m1");
    let message_2 = db::insert_message(&conn, &key, &conversation.id, "user", "").expect("m2");

    let attachment_1 =
        db::insert_attachment(&conn, &key, &app_dir, b"m4a-1", "audio/mp4").expect("attachment 1");
    let attachment_2 =
        db::insert_attachment(&conn, &key, &app_dir, b"m4a-2", "audio/mp4").expect("attachment 2");

    db::link_attachment_to_message(&conn, &key, &message_1.id, &attachment_1.sha256)
        .expect("link 1");
    db::link_attachment_to_message(&conn, &key, &message_2.id, &attachment_2.sha256)
        .expect("link 2");

    let ann_1 = serde_json::json!({
        "schema": "secondloop.audio_transcript.v1",
        "transcript_excerpt": "UNRELATED_ALPHA",
        "transcript_full": "UNRELATED_ALPHA"
    });
    let ann_2 = serde_json::json!({
        "schema": "secondloop.audio_transcript.v1",
        "transcript_excerpt": "TARGET_BETA 越夜越动听",
        "transcript_full": "TARGET_BETA 越夜越动听"
    });

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment_1.sha256,
        "zh-CN",
        "whisper-1",
        &ann_1,
        message_1.created_at_ms,
    )
    .expect("annotation 1");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment_2.sha256,
        "zh-CN",
        "whisper-1",
        &ann_2,
        message_2.created_at_ms,
    )
    .expect("annotation 2");

    let embedder = EmptyContentOrderingEmbedder;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 100).expect("index");

    let results =
        db::search_similar_messages(&conn, &key, &embedder, "越夜越动听", 2).expect("search");
    assert_eq!(results.len(), 2);

    let ids: std::collections::HashSet<String> =
        results.into_iter().map(|item| item.message.id).collect();
    assert!(ids.contains(&message_1.id));
    assert!(ids.contains(&message_2.id));
}

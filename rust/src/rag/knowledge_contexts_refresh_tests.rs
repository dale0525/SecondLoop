use crate::db;
use crate::rag::{try_build_knowledge_contexts_for_tests, Focus};

#[test]
fn rag_context_build_skips_page_recompile_when_pages_are_current() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [85u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");
    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    conn.execute(
        "UPDATE knowledge_rebuild_state SET pages_refresh_required = 0 WHERE state_key = 1",
        [],
    )
    .expect("mark pages current");
    conn.execute_batch(
        r#"
CREATE TRIGGER fail_knowledge_claim_insert_for_rag
BEFORE INSERT ON knowledge_claims
BEGIN
    SELECT RAISE(FAIL, 'unexpected page recompile from rag');
END;
"#,
    )
    .expect("create failing trigger");

    let contexts = try_build_knowledge_contexts_for_tests(
        &conn,
        &key,
        "What language should you answer in?",
        6,
        Focus::ThisThread,
        &conv.id,
        None,
    )
    .expect("build contexts");

    assert!(
        contexts.iter().any(|ctx| ctx.contains("Chinese")),
        "contexts: {contexts:?}"
    );
}

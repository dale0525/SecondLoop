use crate::auth;
use crate::crypto::{derive_root_key, KdfParams};
use crate::db;
use crate::sync;

#[test]
fn secretary_state_roundtrips_between_devices() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopSecretarySyncTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A");

    let pending = db::create_secretary_memory_proposal(
        &conn_a,
        &key_a,
        db::NewSecretaryMemoryProposal {
            source_message_id: Some("message:pending".to_string()),
            kind: "preference".to_string(),
            title: "Morning meetings".to_string(),
            body: "I prefer morning meetings.".to_string(),
            confidence: 0.91,
            source_refs_json: Some(r#"{"message_ids":["message:pending"]}"#.to_string()),
            action_hint: Some("propose".to_string()),
            now_ms: 1_000,
        },
    )
    .expect("create pending proposal");
    let dismissed = db::create_secretary_memory_proposal(
        &conn_a,
        &key_a,
        db::NewSecretaryMemoryProposal {
            source_message_id: Some("message:dismissed".to_string()),
            kind: "fact".to_string(),
            title: "Old role".to_string(),
            body: "I worked with Alice.".to_string(),
            confidence: 0.72,
            source_refs_json: None,
            action_hint: Some("propose".to_string()),
            now_ms: 1_100,
        },
    )
    .expect("create dismissed proposal");
    db::set_secretary_memory_proposal_state(&conn_a, &key_a, &dismissed.id, "dismissed", 1_200)
        .expect("dismiss proposal");
    let accepted = db::create_secretary_memory_proposal(
        &conn_a,
        &key_a,
        db::NewSecretaryMemoryProposal {
            source_message_id: Some("message:accepted".to_string()),
            kind: "constraint".to_string(),
            title: "No late meetings".to_string(),
            body: "I avoid meetings after 5pm.".to_string(),
            confidence: 0.88,
            source_refs_json: Some(r#"{"message_ids":["message:accepted"]}"#.to_string()),
            action_hint: Some("update".to_string()),
            now_ms: 1_300,
        },
    )
    .expect("create accepted proposal");
    let memory = db::create_memory_page_from_proposal(&conn_a, &key_a, &accepted.id, 1_400)
        .expect("accept memory");
    let plan = db::upsert_planning_output(
        &conn_a,
        &key_a,
        db::NewPlanningOutput {
            id: "plan:daily:2026-04-29".to_string(),
            kind: "daily_plan".to_string(),
            title: "Daily plan".to_string(),
            body: "Focus on two items.".to_string(),
            items_json: r#"[{"todo_id":"todo:1"}]"#.to_string(),
            source_refs_json: Some(r#"{"todo_ids":["todo:1"]}"#.to_string()),
            route: "local_rules".to_string(),
            state: "dismissed".to_string(),
            created_at_ms: 1_500,
            updated_at_ms: 1_600,
            expires_at_ms: Some(2_000),
        },
    )
    .expect("upsert planning output");
    let run = db::create_secretary_run(
        &conn_a,
        &key_a,
        db::NewSecretaryRun {
            trigger_kind: "capture".to_string(),
            route: "local_rules".to_string(),
            status: "succeeded".to_string(),
            input_summary: Some("Semantic parse applied".to_string()),
            output_summary: Some("Created todo".to_string()),
            error: None,
            now_ms: 1_700,
        },
    )
    .expect("create run");
    let call = db::create_secretary_tool_call(
        &conn_a,
        &key_a,
        db::NewSecretaryToolCall {
            run_id: run.id.clone(),
            tool_name: "todo.create".to_string(),
            status: "succeeded".to_string(),
            requires_confirmation: false,
            input_json: Some(r#"{"message_id":"message:accepted"}"#.to_string()),
            output_json: Some(r#"{"todo_id":"todo:1"}"#.to_string()),
            now_ms: 1_710,
        },
    )
    .expect("create tool call");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync-secretary",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);
    let pulled = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(pulled > 0);

    let pending_b =
        db::get_secretary_memory_proposal(&conn_b, &key_b, &pending.id).expect("pending on B");
    assert_eq!(pending_b.state, "pending");
    assert_eq!(pending_b.title, "Morning meetings");

    let dismissed_b =
        db::get_secretary_memory_proposal(&conn_b, &key_b, &dismissed.id).expect("dismissed on B");
    assert_eq!(dismissed_b.state, "dismissed");

    let memory_b = db::get_memory_page(&conn_b, &key_b, &memory.page_id).expect("memory on B");
    assert_eq!(memory_b.state, "active");
    assert_eq!(memory_b.title, "No late meetings");

    let plan_b = db::get_planning_output(&conn_b, &key_b, &plan.id).expect("plan on B");
    assert_eq!(plan_b.state, "dismissed");
    assert_eq!(plan_b.items_json, r#"[{"todo_id":"todo:1"}]"#);

    let run_b = db::get_secretary_run(&conn_b, &key_b, &run.id).expect("run on B");
    assert_eq!(run_b.trigger_kind, "capture");
    let calls_b =
        db::list_secretary_tool_calls_for_run(&conn_b, &key_b, &run.id).expect("calls on B");
    assert_eq!(calls_b.len(), 1);
    assert_eq!(calls_b[0].id, call.id);
    assert_eq!(calls_b[0].tool_name, "todo.create");
}

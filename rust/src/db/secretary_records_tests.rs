use super::*;

fn test_key() -> [u8; 32] {
    [7u8; 32]
}

#[test]
fn secretary_records_tables_exist_after_migration() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let user_version: i64 = conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .expect("user_version");
    assert!(user_version >= 51);

    let mut stmt = conn
        .prepare(
            r#"
SELECT name
FROM sqlite_master
WHERE type = 'table'
  AND name IN (
    'secretary_memory_proposals',
    'planning_outputs',
    'secretary_runs',
    'secretary_tool_calls'
  )
ORDER BY name ASC
"#,
        )
        .expect("prepare");
    let names = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query")
        .collect::<std::result::Result<Vec<_>, _>>()
        .expect("collect");

    assert_eq!(
        names,
        vec![
            "planning_outputs".to_string(),
            "secretary_memory_proposals".to_string(),
            "secretary_runs".to_string(),
            "secretary_tool_calls".to_string(),
        ]
    );
}

#[test]
fn secretary_memory_proposal_round_trips_encrypted_and_changes_state() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = test_key();

    let proposal = create_secretary_memory_proposal(
        &conn,
        &key,
        NewSecretaryMemoryProposal {
            source_message_id: Some("m1".to_string()),
            kind: "preference".to_string(),
            title: "Morning meetings".to_string(),
            body: "I prefer morning meetings.".to_string(),
            confidence: 0.92,
            source_refs_json: Some(r#"{"message_ids":["m1"]}"#.to_string()),
            action_hint: Some("propose".to_string()),
            now_ms: 100,
        },
    )
    .expect("create proposal");

    let title_blob: Vec<u8> = conn
        .query_row(
            "SELECT title FROM secretary_memory_proposals WHERE id = ?1",
            params![proposal.id.as_str()],
            |row| row.get(0),
        )
        .expect("title blob");
    assert!(!String::from_utf8_lossy(&title_blob).contains("Morning meetings"));

    let listed = list_secretary_memory_proposals(&conn, &key, None).expect("list proposals");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].title, "Morning meetings");
    assert_eq!(listed[0].body, "I prefer morning meetings.");
    assert_eq!(listed[0].state, "pending");

    let accepted = set_secretary_memory_proposal_state(&conn, &key, &proposal.id, "accepted", 110)
        .expect("accept");
    assert_eq!(accepted.state, "accepted");
    assert_eq!(accepted.accepted_at_ms, Some(110));

    let dismissed =
        set_secretary_memory_proposal_state(&conn, &key, &proposal.id, "dismissed", 120)
            .expect("dismiss");
    assert_eq!(dismissed.state, "dismissed");
    assert_eq!(dismissed.dismissed_at_ms, Some(120));
}

#[test]
fn planning_outputs_filter_expired_records() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = test_key();

    upsert_planning_output(
        &conn,
        &key,
        NewPlanningOutput {
            id: "daily-old".to_string(),
            kind: "daily_plan".to_string(),
            title: "Old plan".to_string(),
            body: "Expired".to_string(),
            items_json: r#"[]"#.to_string(),
            source_refs_json: None,
            route: "local_rules".to_string(),
            state: "active".to_string(),
            created_at_ms: 10,
            updated_at_ms: 10,
            expires_at_ms: Some(20),
        },
    )
    .expect("old plan");
    upsert_planning_output(
        &conn,
        &key,
        NewPlanningOutput {
            id: "daily-current".to_string(),
            kind: "daily_plan".to_string(),
            title: "Current plan".to_string(),
            body: "Useful".to_string(),
            items_json: r#"[{"title":"Focus"}]"#.to_string(),
            source_refs_json: Some(r#"{"todo_ids":["t1"]}"#.to_string()),
            route: "local_rules".to_string(),
            state: "active".to_string(),
            created_at_ms: 30,
            updated_at_ms: 30,
            expires_at_ms: Some(200),
        },
    )
    .expect("current plan");

    let active =
        list_planning_outputs(&conn, &key, Some("daily_plan"), 100, false).expect("active plans");
    assert_eq!(active.len(), 1);
    assert_eq!(active[0].id, "daily-current");
    assert_eq!(active[0].title, "Current plan");
    assert_eq!(active[0].items_json, r#"[{"title":"Focus"}]"#);

    let all = list_planning_outputs(&conn, &key, Some("daily_plan"), 100, true).expect("all plans");
    assert_eq!(all.len(), 2);
}

#[test]
fn secretary_run_tool_calls_round_trip_and_cascade() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = test_key();

    let run = create_secretary_run(
        &conn,
        &key,
        NewSecretaryRun {
            trigger_kind: "capture".to_string(),
            route: "local_rules".to_string(),
            status: "running".to_string(),
            input_summary: Some("User asked to remember a preference".to_string()),
            output_summary: None,
            error: None,
            now_ms: 300,
        },
    )
    .expect("create run");
    let call = create_secretary_tool_call(
        &conn,
        &key,
        NewSecretaryToolCall {
            run_id: run.id.clone(),
            tool_name: "memory.propose".to_string(),
            status: "succeeded".to_string(),
            requires_confirmation: true,
            input_json: Some(r#"{"source":"m1"}"#.to_string()),
            output_json: Some(r#"{"proposal_id":"p1"}"#.to_string()),
            now_ms: 301,
        },
    )
    .expect("create tool call");

    let calls = list_secretary_tool_calls_for_run(&conn, &key, &run.id).expect("list calls");
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].id, call.id);
    assert_eq!(calls[0].tool_name, "memory.propose");
    assert_eq!(calls[0].input_json.as_deref(), Some(r#"{"source":"m1"}"#));
    assert!(calls[0].requires_confirmation);

    conn.execute(
        "DELETE FROM secretary_runs WHERE id = ?1",
        params![run.id.as_str()],
    )
    .expect("delete run");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM secretary_tool_calls", [], |row| {
            row.get(0)
        })
        .expect("count calls");
    assert_eq!(count, 0);
}

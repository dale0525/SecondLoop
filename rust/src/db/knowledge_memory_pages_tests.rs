use super::*;

fn test_key() -> [u8; 32] {
    [9u8; 32]
}

#[test]
fn accepting_memory_proposal_creates_knowledge_page_and_history() {
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
            confidence: 0.91,
            source_refs_json: Some(r#"{"message_ids":["m1"]}"#.to_string()),
            action_hint: Some("propose".to_string()),
            now_ms: 100,
        },
    )
    .expect("proposal");

    let page =
        create_memory_page_from_proposal(&conn, &key, &proposal.id, 200).expect("accept into page");

    assert_eq!(page.page_type, "memory");
    assert_eq!(page.state, "active");
    assert_eq!(page.title, "Morning meetings");
    assert_eq!(page.summary, "I prefer morning meetings.");
    assert_eq!(page.body, "I prefer morning meetings.");
    assert_eq!(page.primary_evidence_json, r#"{"message_ids":["m1"]}"#);
    assert_eq!(page.source_document_ids_json, r#"["m1"]"#);
    assert!(!page.human_corrected);

    let stored_state: String = conn
        .query_row(
            "SELECT state FROM secretary_memory_proposals WHERE id = ?1",
            params![proposal.id.as_str()],
            |row| row.get(0),
        )
        .expect("proposal state");
    assert_eq!(stored_state, "accepted");

    let history: (String, String, i64) = conn
        .query_row(
            "SELECT change_type, actor, created_at_ms FROM knowledge_page_history WHERE page_id = ?1",
            params![page.page_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("history");
    assert_eq!(
        history,
        ("memory.accepted".to_string(), "user".to_string(), 200)
    );
}

#[test]
fn correcting_memory_page_sets_manual_fields_and_snapshots_version() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = test_key();
    let proposal = create_secretary_memory_proposal(
        &conn,
        &key,
        NewSecretaryMemoryProposal {
            source_message_id: Some("m2".to_string()),
            kind: "fact".to_string(),
            title: "Old title".to_string(),
            body: "Old body".to_string(),
            confidence: 0.8,
            source_refs_json: None,
            action_hint: None,
            now_ms: 100,
        },
    )
    .expect("proposal");
    let page = create_memory_page_from_proposal(&conn, &key, &proposal.id, 200).expect("page");

    let corrected = correct_memory_page(
        &conn,
        &key,
        CorrectMemoryPageInput {
            page_id: page.page_id.clone(),
            title: "Correct title".to_string(),
            summary: "Correct summary".to_string(),
            body: "Correct body".to_string(),
            reason: Some("User corrected wording".to_string()),
            now_ms: 300,
        },
    )
    .expect("correct");

    assert_eq!(corrected.title, "Correct title");
    assert_eq!(corrected.summary, "Correct summary");
    assert_eq!(corrected.body, "Correct body");
    assert!(corrected.human_corrected);

    let version_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_page_versions WHERE page_id = ?1",
            params![page.page_id.as_str()],
            |row| row.get(0),
        )
        .expect("versions");
    assert_eq!(version_count, 1);

    let history: (String, String, String) = conn
        .query_row(
            "SELECT change_type, actor, reason FROM knowledge_page_history WHERE page_id = ?1 ORDER BY created_at_ms DESC LIMIT 1",
            params![page.page_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("history");
    assert_eq!(
        history,
        (
            "memory.corrected".to_string(),
            "user".to_string(),
            "User corrected wording".to_string(),
        )
    );
}

#[test]
fn memory_pages_can_archive_and_restore() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = test_key();
    let proposal = create_secretary_memory_proposal(
        &conn,
        &key,
        NewSecretaryMemoryProposal {
            source_message_id: None,
            kind: "fact".to_string(),
            title: "Archive me".to_string(),
            body: "Temporary memory".to_string(),
            confidence: 0.7,
            source_refs_json: None,
            action_hint: None,
            now_ms: 100,
        },
    )
    .expect("proposal");
    let page = create_memory_page_from_proposal(&conn, &key, &proposal.id, 200).expect("page");

    let archived = archive_memory_page(&conn, &key, &page.page_id, 300).expect("archive");
    assert_eq!(archived.state, "archived");
    let active = list_memory_pages(&conn, &key, Some("active")).expect("active list");
    assert!(active.is_empty());

    let restored = restore_memory_page(&conn, &key, &page.page_id, 400).expect("restore");
    assert_eq!(restored.state, "active");
    let active = list_memory_pages(&conn, &key, Some("active")).expect("active list");
    assert_eq!(active.len(), 1);
}

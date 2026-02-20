use rusqlite::{params, Connection};
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[derive(Clone, Debug)]
enum FocusScope {
    Conversation,
    All,
    TopicThread(String),
}

#[derive(Clone, Debug)]
struct QueryScope {
    focus: FocusScope,
    start_ms: Option<i64>,
    end_ms: Option<i64>,
    include_tag_ids: Vec<String>,
    exclude_tag_ids: Vec<String>,
}

fn list_base_message_ids(
    conn: &Connection,
    conversation_id: &str,
    focus: &FocusScope,
) -> anyhow::Result<Vec<String>> {
    match focus {
        FocusScope::Conversation => {
            let mut stmt = conn.prepare(
                r#"SELECT id
                   FROM messages
                   WHERE conversation_id = ?1
                     AND COALESCE(is_deleted, 0) = 0
                   ORDER BY created_at DESC, id DESC"#,
            )?;
            let mut rows = stmt.query(params![conversation_id])?;
            let mut out = Vec::<String>::new();
            while let Some(row) = rows.next()? {
                out.push(row.get(0)?);
            }
            Ok(out)
        }
        FocusScope::All => {
            let mut stmt = conn.prepare(
                r#"SELECT id
                   FROM messages
                   WHERE COALESCE(is_deleted, 0) = 0
                   ORDER BY created_at DESC, id DESC"#,
            )?;
            let mut rows = stmt.query([])?;
            let mut out = Vec::<String>::new();
            while let Some(row) = rows.next()? {
                out.push(row.get(0)?);
            }
            Ok(out)
        }
        FocusScope::TopicThread(thread_id) => db::list_topic_thread_message_ids(conn, thread_id),
    }
}

fn list_scoped_message_ids(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    scope: &QueryScope,
) -> anyhow::Result<Vec<String>> {
    let mut base = list_base_message_ids(conn, conversation_id, &scope.focus)?;

    if !scope.include_tag_ids.is_empty() {
        let include_ids = match scope.focus {
            FocusScope::All => db::list_message_ids_by_tag_ids_all(conn, &scope.include_tag_ids)?,
            _ => db::list_message_ids_by_tag_ids(conn, conversation_id, &scope.include_tag_ids)?,
        };
        let include_set = include_ids
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();
        base.retain(|message_id| include_set.contains(message_id));
    }

    if !scope.exclude_tag_ids.is_empty() {
        let exclude_ids = match scope.focus {
            FocusScope::All => db::list_message_ids_by_tag_ids_all(conn, &scope.exclude_tag_ids)?,
            _ => db::list_message_ids_by_tag_ids(conn, conversation_id, &scope.exclude_tag_ids)?,
        };
        let exclude_set = exclude_ids
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();
        base.retain(|message_id| !exclude_set.contains(message_id));
    }

    if let (Some(start), Some(end)) = (scope.start_ms, scope.end_ms) {
        base.retain(|message_id| {
            db::get_message_by_id_optional(conn, key, message_id)
                .ok()
                .flatten()
                .is_some_and(|message| {
                    message.created_at_ms >= start && message.created_at_ms < end
                })
        });
    }

    Ok(base)
}

#[test]
fn query_scope_matrix_covers_focus_time_and_include_exclude_tags() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let main = db::create_conversation(&conn, &key, "Main").expect("create main conversation");
    let side = db::create_conversation(&conn, &key, "Side").expect("create side conversation");

    let m_main_old = db::insert_message(&conn, &key, &main.id, "user", "main old work")
        .expect("insert m_main_old");
    let m_main_recent =
        db::insert_message(&conn, &key, &main.id, "user", "main recent work travel")
            .expect("insert m_main_recent");
    let m_main_other = db::insert_message(&conn, &key, &main.id, "user", "main recent personal")
        .expect("insert m_main_other");
    let m_side_recent = db::insert_message(&conn, &key, &side.id, "user", "side recent work")
        .expect("insert m_side_recent");

    let base = 1_700_000_000_000i64;
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![m_main_old.id, base - 10 * 24 * 60 * 60 * 1000],
    )
    .expect("set old message time");
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![m_main_recent.id, base - 2 * 24 * 60 * 60 * 1000],
    )
    .expect("set main recent time");
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![m_main_other.id, base - 24 * 60 * 60 * 1000],
    )
    .expect("set main other time");
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![m_side_recent.id, base - 24 * 60 * 60 * 1000],
    )
    .expect("set side recent time");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    let travel = db::upsert_tag(&conn, &key, "travel").expect("upsert travel tag");
    let personal = db::upsert_tag(&conn, &key, "personal").expect("upsert personal tag");

    db::set_message_tags(&conn, &key, &m_main_old.id, std::slice::from_ref(&work.id))
        .expect("tag main old");
    db::set_message_tags(
        &conn,
        &key,
        &m_main_recent.id,
        &[work.id.clone(), travel.id.clone()],
    )
    .expect("tag main recent");
    db::set_message_tags(
        &conn,
        &key,
        &m_main_other.id,
        std::slice::from_ref(&personal.id),
    )
    .expect("tag main other");
    db::set_message_tags(
        &conn,
        &key,
        &m_side_recent.id,
        std::slice::from_ref(&work.id),
    )
    .expect("tag side recent");

    let thread =
        db::create_topic_thread(&conn, &key, &main.id, Some("Main thread")).expect("create thread");
    db::set_topic_thread_message_ids(
        &conn,
        &key,
        &thread.id,
        &[m_main_recent.id.clone(), m_main_other.id.clone()],
    )
    .expect("set thread messages");

    let week_scope = (base - 7 * 24 * 60 * 60 * 1000, base);

    let matrix = vec![
        (
            "conversation include work",
            QueryScope {
                focus: FocusScope::Conversation,
                start_ms: None,
                end_ms: None,
                include_tag_ids: vec![work.id.clone()],
                exclude_tag_ids: vec![],
            },
            vec![m_main_recent.id.clone(), m_main_old.id.clone()],
        ),
        (
            "conversation include work exclude travel",
            QueryScope {
                focus: FocusScope::Conversation,
                start_ms: None,
                end_ms: None,
                include_tag_ids: vec![work.id.clone()],
                exclude_tag_ids: vec![travel.id.clone()],
            },
            vec![m_main_old.id.clone()],
        ),
        (
            "conversation include work in week",
            QueryScope {
                focus: FocusScope::Conversation,
                start_ms: Some(week_scope.0),
                end_ms: Some(week_scope.1),
                include_tag_ids: vec![work.id.clone()],
                exclude_tag_ids: vec![],
            },
            vec![m_main_recent.id.clone()],
        ),
        (
            "all memories include work in week",
            QueryScope {
                focus: FocusScope::All,
                start_ms: Some(week_scope.0),
                end_ms: Some(week_scope.1),
                include_tag_ids: vec![work.id.clone()],
                exclude_tag_ids: vec![],
            },
            vec![m_side_recent.id.clone(), m_main_recent.id.clone()],
        ),
        (
            "topic thread include work in week",
            QueryScope {
                focus: FocusScope::TopicThread(thread.id.clone()),
                start_ms: Some(week_scope.0),
                end_ms: Some(week_scope.1),
                include_tag_ids: vec![work.id.clone()],
                exclude_tag_ids: vec![],
            },
            vec![m_main_recent.id.clone()],
        ),
        (
            "topic thread include work exclude travel",
            QueryScope {
                focus: FocusScope::TopicThread(thread.id.clone()),
                start_ms: None,
                end_ms: None,
                include_tag_ids: vec![work.id],
                exclude_tag_ids: vec![travel.id],
            },
            vec![],
        ),
    ];

    for (case_name, scope, expected_ids) in matrix {
        let actual_ids = list_scoped_message_ids(&conn, &key, &main.id, &scope)
            .unwrap_or_else(|_| panic!("scope query failed for case: {case_name}"));
        assert_eq!(actual_ids, expected_ids, "case: {case_name}");
    }
}

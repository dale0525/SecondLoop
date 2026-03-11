use tempfile::tempdir;

use crate::auth;
use crate::crypto::KdfParams;

use super::*;

#[test]
fn collect_scoped_contexts_applies_time_window_with_tag_filter() {
    use rusqlite::params;

    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let old_work = db::insert_message(&conn, &key, &conversation.id, "user", "work monday")
        .expect("insert old_work");
    let in_window_work = db::insert_message(&conn, &key, &conversation.id, "user", "work friday")
        .expect("insert in_window_work");
    let in_window_other =
        db::insert_message(&conn, &key, &conversation.id, "user", "personal friday")
            .expect("insert in_window_other");

    let base = 1_700_000_000_000i64;
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![old_work.id, base - 8 * 24 * 60 * 60 * 1000],
    )
    .expect("set old_work time");
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![in_window_work.id, base - 2 * 24 * 60 * 60 * 1000],
    )
    .expect("set in_window_work time");
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![in_window_other.id, base - 2 * 24 * 60 * 60 * 1000],
    )
    .expect("set in_window_other time");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    db::set_message_tags(&conn, &key, &old_work.id, std::slice::from_ref(&work.id))
        .expect("set old_work tags");
    db::set_message_tags(
        &conn,
        &key,
        &in_window_work.id,
        std::slice::from_ref(&work.id),
    )
    .expect("set in_window_work tags");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        std::slice::from_ref(&work.id),
        &[],
        10,
        Some(TimeScope {
            start_ms_inclusive: base - 7 * 24 * 60 * 60 * 1000,
            end_ms_exclusive: base,
        }),
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("work friday"));
}

#[test]
fn collect_scoped_contexts_applies_time_window_without_tag_filters() {
    use rusqlite::params;

    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let old_note = db::insert_message(&conn, &key, &conversation.id, "user", "old note")
        .expect("insert old_note");
    let in_window_note =
        db::insert_message(&conn, &key, &conversation.id, "user", "in window note")
            .expect("insert in_window_note");

    let base = 1_700_000_000_000i64;
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![old_note.id, base - 20 * 24 * 60 * 60 * 1000],
    )
    .expect("set old_note time");
    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![in_window_note.id, base - 2 * 24 * 60 * 60 * 1000],
    )
    .expect("set in_window_note time");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        &[],
        &[],
        10,
        Some(TimeScope {
            start_ms_inclusive: base - 7 * 24 * 60 * 60 * 1000,
            end_ms_exclusive: base,
        }),
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("in window note"));
}

#[test]
fn collect_scoped_contexts_supports_all_memories_scope_for_tag_filter() {
    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation_main =
        db::create_conversation(&conn, &key, "Main").expect("create main conversation");
    let conversation_side =
        db::create_conversation(&conn, &key, "Side").expect("create side conversation");

    let main_work =
        db::insert_message(&conn, &key, &conversation_main.id, "user", "main work note")
            .expect("insert main_work");
    let side_work =
        db::insert_message(&conn, &key, &conversation_side.id, "user", "side work note")
            .expect("insert side_work");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    db::set_message_tags(&conn, &key, &main_work.id, std::slice::from_ref(&work.id))
        .expect("set main_work tags");
    db::set_message_tags(&conn, &key, &side_work.id, std::slice::from_ref(&work.id))
        .expect("set side_work tags");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation_main.id,
        std::slice::from_ref(&work.id),
        &[],
        10,
        None,
        ScopedFocus::AllMemories,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 2);
    assert!(contexts
        .iter()
        .any(|value| value.contains("main work note")));
    assert!(contexts
        .iter()
        .any(|value| value.contains("side work note")));
}

#[test]
fn collect_scoped_contexts_applies_exclude_tags_without_include_tags() {
    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");

    let m_work = db::insert_message(&conn, &key, &conversation.id, "user", "work note")
        .expect("insert m_work");
    let _m_personal = db::insert_message(&conn, &key, &conversation.id, "user", "personal note")
        .expect("insert m_personal");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    db::set_message_tags(&conn, &key, &m_work.id, std::slice::from_ref(&work.id))
        .expect("set m_work tags");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        &[],
        std::slice::from_ref(&work.id),
        10,
        None,
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("personal note"));
    assert!(contexts.iter().all(|v| !v.contains("work note")));
}

#[test]
fn collect_scoped_contexts_appends_message_deeplink() {
    use rusqlite::params;

    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let remembered = db::insert_message(&conn, &key, &conversation.id, "user", "remembered note")
        .expect("insert remembered");

    conn.execute(
        "UPDATE messages SET created_at = ?2 WHERE id = ?1",
        params![remembered.id, 1_700_000_000_000i64],
    )
    .expect("set remembered time");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        &[],
        &[],
        10,
        Some(TimeScope {
            start_ms_inclusive: 0,
            end_ms_exclusive: 1_800_000_000_000i64,
        }),
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("remembered note"));
    assert!(contexts[0].contains("secondloop://message/"));
}

#[test]
fn collect_scoped_contexts_trims_message_id_in_citation() {
    use rusqlite::params;

    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let remembered = db::insert_message(&conn, &key, &conversation.id, "user", "remembered note")
        .expect("insert remembered");

    conn.execute("PRAGMA foreign_keys = OFF", [])
        .expect("disable foreign keys for test rewrite");
    conn.execute(
        "UPDATE messages SET id = ?2, created_at = ?3 WHERE id = ?1",
        params![remembered.id, "  spaced-id  ", 1_700_000_000_000i64],
    )
    .expect("rewrite remembered id and time");
    conn.execute("PRAGMA foreign_keys = ON", [])
        .expect("re-enable foreign keys after test rewrite");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        &[],
        &[],
        10,
        Some(TimeScope {
            start_ms_inclusive: 0,
            end_ms_exclusive: 1_800_000_000_000i64,
        }),
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("[History](secondloop://message/spaced-id)"));
    assert!(!contexts[0].contains("[History](secondloop://message/  spaced-id  )"));
}

#[test]
fn collect_scoped_contexts_applies_exclude_tags_after_include_tags() {
    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");

    let m_work_only = db::insert_message(&conn, &key, &conversation.id, "user", "work only")
        .expect("insert m_work_only");
    let m_work_social =
        db::insert_message(&conn, &key, &conversation.id, "user", "work and social")
            .expect("insert m_work_social");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    let social = db::upsert_tag(&conn, &key, "social").expect("upsert social tag");

    db::set_message_tags(&conn, &key, &m_work_only.id, std::slice::from_ref(&work.id))
        .expect("set m_work_only tags");
    db::set_message_tags(
        &conn,
        &key,
        &m_work_social.id,
        &[work.id.clone(), social.id.clone()],
    )
    .expect("set m_work_social tags");

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        std::slice::from_ref(&work.id),
        std::slice::from_ref(&social.id),
        10,
        None,
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("work only"));
}

#[test]
fn resolve_scoped_include_tag_ids_ignores_single_character_non_ascii_tags() {
    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    let single_char = db::upsert_tag(&conn, &key, "工").expect("upsert single-char tag");

    let include_tag_ids = resolve_scoped_include_tag_ids(&conn, &key, "写一份工作周报", &[])
        .expect("resolve include tag ids");

    assert!(include_tag_ids.contains(&work.id));
    assert!(!include_tag_ids.contains(&single_char.id));
}

#[test]
fn resolve_scoped_include_tag_ids_avoids_two_character_cjk_alias_inside_compound_words() {
    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");

    let social_worker_scope =
        resolve_scoped_include_tag_ids(&conn, &key, "帮我列出社会工作者需要的技能", &[])
            .expect("resolve social worker scope");
    let workload_scope = resolve_scoped_include_tag_ids(&conn, &key, "最近工作量有点大", &[])
        .expect("resolve workload scope");

    assert!(!social_worker_scope.contains(&work.id));
    assert!(!workload_scope.contains(&work.id));
}

#[test]
fn resolve_scoped_contexts_snapshot_infers_scope_and_collects_contexts() {
    use rusqlite::params;

    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");

    let work_note = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "prepare client update",
    )
    .expect("insert work_note");
    let personal_note = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "book dentist appointment",
    )
    .expect("insert personal_note");

    let base = 1_700_000_000_000i64;
    for message_id in [&work_note.id, &personal_note.id] {
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![message_id, base - 2 * 24 * 60 * 60 * 1000],
        )
        .expect("set message time");
    }

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    let personal = db::upsert_tag(&conn, &key, "personal").expect("upsert personal tag");

    db::set_message_tags(&conn, &key, &work_note.id, std::slice::from_ref(&work.id))
        .expect("tag work_note");
    db::set_message_tags(
        &conn,
        &key,
        &personal_note.id,
        std::slice::from_ref(&personal.id),
    )
    .expect("tag personal_note");

    let (include_tag_ids, contexts) = resolve_scoped_contexts_snapshot(
        &conn,
        &key,
        &conversation.id,
        "写一份工作周报",
        &[],
        &[],
        10,
        Some(TimeScope {
            start_ms_inclusive: base - 7 * 24 * 60 * 60 * 1000,
            end_ms_exclusive: base,
        }),
        ScopedFocus::Conversation,
    )
    .expect("resolve scoped contexts snapshot");

    assert_eq!(include_tag_ids, vec![work.id.clone()]);
    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("prepare client update"));
    assert!(contexts.iter().all(|value| !value.contains("dentist")));
}

#[test]
fn resolve_scoped_include_tag_ids_infers_ascii_scope_across_full_width_punctuation() {
    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");

    let include_tag_ids = resolve_scoped_include_tag_ids(&conn, &key, "work，weekly report", &[])
        .expect("resolve include tag ids");

    assert_eq!(include_tag_ids, vec![work.id.clone()]);
}

#[test]
fn resolve_scoped_include_tag_ids_infers_work_scope_from_question() {
    use rusqlite::params;

    let temp = tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");

    let work_note = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "prepare client update",
    )
    .expect("insert work_note");
    let personal_note = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "book dentist appointment",
    )
    .expect("insert personal_note");
    let hobby_note = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "practice guitar for weekend jam",
    )
    .expect("insert hobby_note");

    let base = 1_700_000_000_000i64;
    for message_id in [&work_note.id, &personal_note.id, &hobby_note.id] {
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![message_id, base - 2 * 24 * 60 * 60 * 1000],
        )
        .expect("set message time");
    }

    let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
    let personal = db::upsert_tag(&conn, &key, "personal").expect("upsert personal tag");
    let hobby = db::upsert_tag(&conn, &key, "hobby").expect("upsert hobby tag");

    db::set_message_tags(&conn, &key, &work_note.id, std::slice::from_ref(&work.id))
        .expect("tag work_note");
    db::set_message_tags(
        &conn,
        &key,
        &personal_note.id,
        std::slice::from_ref(&personal.id),
    )
    .expect("tag personal_note");
    db::set_message_tags(&conn, &key, &hobby_note.id, std::slice::from_ref(&hobby.id))
        .expect("tag hobby_note");

    let include_tag_ids = resolve_scoped_include_tag_ids(&conn, &key, "写一份工作周报", &[])
        .expect("resolve include tag ids");

    assert_eq!(include_tag_ids, vec![work.id.clone()]);

    let contexts = collect_scoped_contexts(
        &conn,
        &key,
        &conversation.id,
        &include_tag_ids,
        &[],
        10,
        Some(TimeScope {
            start_ms_inclusive: base - 7 * 24 * 60 * 60 * 1000,
            end_ms_exclusive: base,
        }),
        ScopedFocus::Conversation,
    )
    .expect("collect contexts");

    assert_eq!(contexts.len(), 1);
    assert!(contexts[0].contains("prepare client update"));
    assert!(contexts.iter().all(|value| !value.contains("dentist")));
    assert!(contexts.iter().all(|value| !value.contains("guitar")));
}

use std::collections::BTreeSet;

use tempfile::tempdir;

use super::*;

fn tag_names(tags: Vec<Tag>) -> BTreeSet<String> {
    tags.into_iter()
        .map(|tag| normalize_tag_name(&tag.name))
        .collect()
}

#[test]
fn insert_message_applies_manual_hash_tags() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let key = [41u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "   #ProjectX notes #Urgent\nhello there",
    )
    .expect("insert message");

    let names = tag_names(list_message_tags(&conn, &key, &message.id).expect("message tags"));
    assert_eq!(
        names,
        BTreeSet::from(["projectx".to_string(), "urgent".to_string()])
    );
}

#[test]
fn edit_message_replaces_manual_hash_tags_and_preserves_other_tags() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let key = [43u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "#alpha\nhello there")
        .expect("insert message");

    let alpha = upsert_tag(&conn, &key, "alpha").expect("alpha");
    let picker = upsert_tag(&conn, &key, "picker").expect("picker");
    set_message_tags(
        &conn,
        &key,
        &message.id,
        &[alpha.id.clone(), picker.id.clone()],
    )
    .expect("seed tags");

    edit_message(&conn, &key, &message.id, "#beta\nhello there").expect("edit message");

    let names = tag_names(list_message_tags(&conn, &key, &message.id).expect("message tags"));
    assert_eq!(
        names,
        BTreeSet::from(["beta".to_string(), "picker".to_string()])
    );
}

#[test]
fn manual_hash_tags_over_budget_skip_autofill() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let key = [47u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "#alpha #beta #gamma #delta\n整理报销预算",
    )
    .expect("insert message");

    let names = tag_names(list_message_tags(&conn, &key, &message.id).expect("message tags"));
    assert_eq!(
        names,
        BTreeSet::from([
            "alpha".to_string(),
            "beta".to_string(),
            "delta".to_string(),
            "gamma".to_string(),
        ])
    );
}

#[test]
fn delete_tag_removes_bindings_and_manual_tokens_from_messages() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let key = [53u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message_with_manual =
        insert_message(&conn, &key, &conversation.id, "user", "#alpha #beta\nbody")
            .expect("insert manual message");
    let message_plain = insert_message(&conn, &key, &conversation.id, "user", "plain body")
        .expect("insert plain message");

    let alpha = upsert_tag(&conn, &key, "alpha").expect("alpha");
    let beta = upsert_tag(&conn, &key, "beta").expect("beta");
    set_message_tags(
        &conn,
        &key,
        &message_with_manual.id,
        &[alpha.id.clone(), beta.id.clone()],
    )
    .expect("seed manual message tags");
    set_message_tags(&conn, &key, &message_plain.id, &[alpha.id.clone()]).expect("seed plain tags");

    delete_tag(&conn, &key, &alpha.id).expect("delete tag");

    let message =
        get_message_by_id(&conn, &key, &message_with_manual.id).expect("read manual message");
    assert_eq!(message.content, "#beta\nbody");

    let manual_names =
        tag_names(list_message_tags(&conn, &key, &message_with_manual.id).expect("manual tags"));
    assert_eq!(manual_names, BTreeSet::from(["beta".to_string()]));

    let plain = get_message_by_id(&conn, &key, &message_plain.id).expect("read plain message");
    assert_eq!(plain.content, "plain body");
    let plain_names =
        tag_names(list_message_tags(&conn, &key, &message_plain.id).expect("plain tags"));
    assert!(plain_names.is_empty());

    let all_names = tag_names(list_tags(&conn, &key).expect("list tags"));
    assert!(!all_names.contains("alpha"));
    assert!(all_names.contains("beta"));
}

#[test]
fn manual_tag_autofill_and_delete_flow_stays_consistent() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");

    let key = [59u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "#alpha\ntrip budget docs",
    )
    .expect("insert message");

    let attachment_a =
        insert_attachment(&conn, &key, &app_dir, b"flow-a", "image/png").expect("attachment a");
    let attachment_b =
        insert_attachment(&conn, &key, &app_dir, b"flow-b", "image/png").expect("attachment b");
    link_attachment_to_message(&conn, &key, &message.id, &attachment_a.sha256).expect("link a");
    link_attachment_to_message(&conn, &key, &message.id, &attachment_b.sha256).expect("link b");

    let payload = serde_json::json!({
        "suggested_tags": ["finance", "travel", "work"]
    });
    mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment_a.sha256,
        "und",
        "vision.v1",
        &payload,
        12_000,
    )
    .expect("annotation a ok");
    mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment_b.sha256,
        "und",
        "vision.v1",
        &payload,
        13_000,
    )
    .expect("annotation b ok");

    let alpha = upsert_tag(&conn, &key, "alpha").expect("alpha");
    delete_tag(&conn, &key, &alpha.id).expect("delete alpha");

    let reloaded = get_message_by_id(&conn, &key, &message.id).expect("reloaded message");
    assert_eq!(reloaded.content, "trip budget docs");

    let names = tag_names(list_message_tags(&conn, &key, &message.id).expect("message tags"));
    assert_eq!(
        names,
        BTreeSet::from(["finance".to_string(), "travel".to_string()])
    );
}

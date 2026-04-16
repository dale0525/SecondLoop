use super::*;

#[test]
fn apply_detached_ask_completion_once_is_idempotent() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [41u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");

    let first = apply_detached_ask_completion_once(
        &conn,
        &key,
        "req_detached_idempotent_1",
        &conversation.id,
        "question_a",
        "answer_a",
        None,
    )
    .expect("first apply");
    assert!(first);

    let second = apply_detached_ask_completion_once(
        &conn,
        &key,
        "req_detached_idempotent_1",
        &conversation.id,
        "question_b_should_not_insert",
        "answer_b_should_not_insert",
        None,
    )
    .expect("second apply");
    assert!(!second);

    let messages = list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(
        messages.len(),
        2,
        "should only keep first user/assistant pair"
    );
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[0].content, "question_a");
    assert_eq!(messages[1].role, "assistant");
    assert_eq!(messages[1].content, "answer_a");
}

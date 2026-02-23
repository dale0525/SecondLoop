use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn list_messages_page_paginates_from_latest_without_gaps_or_duplicates() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &key).expect("loop home");

    for i in 1..=5 {
        db::insert_message(&conn, &key, &conv.id, "user", &format!("m{i}"))
            .expect("insert message");
        std::thread::sleep(std::time::Duration::from_millis(2));
    }

    let page1 = db::list_messages_page(&conn, &key, &conv.id, None, None, 2).expect("page1");
    assert_eq!(page1.len(), 2);
    assert_eq!(page1[0].content, "m5");
    assert_eq!(page1[1].content, "m4");

    let cursor = &page1[1];
    let page2 = db::list_messages_page(
        &conn,
        &key,
        &conv.id,
        Some(cursor.created_at_ms),
        Some(&cursor.id),
        10,
    )
    .expect("page2");
    assert_eq!(page2.len(), 3);
    assert_eq!(page2[0].content, "m3");
    assert_eq!(page2[1].content, "m2");
    assert_eq!(page2[2].content, "m1");

    let cursor2 = &page2[2];
    let page3 = db::list_messages_page(
        &conn,
        &key,
        &conv.id,
        Some(cursor2.created_at_ms),
        Some(&cursor2.id),
        10,
    )
    .expect("page3");
    assert!(page3.is_empty());
}

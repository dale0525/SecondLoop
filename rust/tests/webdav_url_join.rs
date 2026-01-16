use secondloop_rust::sync::webdav::join_base_url_and_path;

#[test]
fn webdav_url_join_preserves_base_path() {
    assert_eq!(
        join_base_url_and_path("https://example.com/dav/", "/SecondLoopTest/deviceA/ops/"),
        "https://example.com/dav/SecondLoopTest/deviceA/ops/"
    );
    assert_eq!(
        join_base_url_and_path("https://example.com/dav", "SecondLoopTest/deviceA/ops/"),
        "https://example.com/dav/SecondLoopTest/deviceA/ops/"
    );
}

use secondloop_rust::sync::webdav::parse_propfind_multistatus;

#[test]
fn webdav_propfind_parses_children_and_strips_base_path() {
    let xml = r#"
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/SecondLoopTest/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/SecondLoopTest/deviceA</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/SecondLoopTest/readme.txt</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
"#;

    let entries = parse_propfind_multistatus("/dav/", "/SecondLoopTest/", xml.as_bytes())
        .expect("parse");

    assert!(entries.contains(&"/SecondLoopTest/deviceA/".to_string()));
    assert!(entries.contains(&"/SecondLoopTest/readme.txt".to_string()));
    assert_eq!(entries.len(), 2);
}


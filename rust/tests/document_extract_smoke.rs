use std::io::{Cursor, Write};

use secondloop_rust::content_extract;

fn build_minimal_docx_bytes(paragraphs: &[&str]) -> Vec<u8> {
    // Our v1 extractor only needs `word/document.xml`.
    let mut xml = String::from(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>"#,
    );
    for p in paragraphs {
        xml.push_str("<w:p><w:r><w:t>");
        xml.push_str(p);
        xml.push_str("</w:t></w:r></w:p>");
    }
    xml.push_str("</w:body></w:document>");

    let mut out = Cursor::new(Vec::<u8>::new());
    {
        let mut zip = zip::ZipWriter::new(&mut out);
        let options =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        zip.start_file("word/document.xml", options)
            .expect("start_file");
        zip.write_all(xml.as_bytes()).expect("write xml");
        zip.finish().expect("finish zip");
    }
    out.into_inner()
}

fn build_minimal_pdf_with_stream(stream_body: &str) -> Vec<u8> {
    // Extremely small, single-page PDF with a controllable content stream.
    // Offsets are computed dynamically.
    let mut parts: Vec<Vec<u8>> = Vec::new();
    parts.push(b"%PDF-1.1\n".to_vec());

    let obj1 = b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".to_vec();
    let obj2 = b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n".to_vec();
    let obj3 = b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n".to_vec();

    let stream = if stream_body.ends_with('\n') {
        stream_body.to_string()
    } else {
        format!("{stream_body}\n")
    };
    let obj4 = format!(
        "4 0 obj\n<< /Length {} >>\nstream\n{}endstream\nendobj\n",
        stream.len(),
        stream
    )
    .into_bytes();
    let obj5 =
        b"5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n".to_vec();

    parts.push(obj1);
    parts.push(obj2);
    parts.push(obj3);
    parts.push(obj4);
    parts.push(obj5);

    let mut offsets: Vec<usize> = Vec::new();
    let mut cur = 0usize;
    for p in &parts {
        offsets.push(cur);
        cur += p.len();
    }

    let xref_start = cur;
    let mut xref = String::new();
    xref.push_str("xref\n0 6\n");
    xref.push_str("0000000000 65535 f \n");
    for offset in offsets.iter().take(6).skip(1) {
        xref.push_str(&format!("{:010} 00000 n \n", offset));
    }
    let trailer = format!(
        "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{}\n%%EOF\n",
        xref_start
    );

    let mut out = Vec::<u8>::new();
    for p in parts {
        out.extend_from_slice(&p);
    }
    out.extend_from_slice(xref.as_bytes());
    out.extend_from_slice(trailer.as_bytes());
    out
}

fn build_minimal_pdf_with_text(text: &str) -> Vec<u8> {
    build_minimal_pdf_with_stream(&format!("BT /F1 24 Tf 72 120 Td ({text}) Tj ET"))
}

fn build_minimal_pdf_without_text() -> Vec<u8> {
    build_minimal_pdf_with_stream("")
}

#[test]
fn document_extract_smoke_docx() {
    let docx = build_minimal_docx_bytes(&["Hello", "World"]);
    let docx_res = content_extract::extract_document(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        &docx,
    )
    .expect("extract docx");
    assert!(docx_res.full_text.contains("Hello"));
    assert!(docx_res.full_text.contains("World"));
    assert!(!docx_res.needs_ocr);
}

#[test]
fn document_extract_smoke_pdf_text() {
    let pdf = build_minimal_pdf_with_text("Hello PDF");
    let pdf_res = content_extract::extract_document("application/pdf", &pdf).expect("extract pdf");
    assert!(pdf_res.full_text.contains("Hello PDF"));
    assert!(!pdf_res.needs_ocr);
    assert_eq!(pdf_res.page_count, Some(1));
}

#[test]
fn document_extract_smoke_pdf_without_text_marks_needs_ocr() {
    let pdf = build_minimal_pdf_without_text();
    let pdf_res = content_extract::extract_document("application/pdf", &pdf).expect("extract pdf");
    assert!(pdf_res.full_text.trim().is_empty());
    assert!(pdf_res.excerpt.trim().is_empty());
    assert!(pdf_res.needs_ocr);
    assert_eq!(pdf_res.page_count, Some(1));
}

#[test]
fn document_extract_smoke_html_strips_tags() {
    let html = br#"<html><head><title>T</title><style>bad</style></head><body><p>Hello</p><script>bad()</script></body></html>"#;
    let html_res = content_extract::extract_document("text/html", html).expect("extract html");
    assert!(html_res.full_text.contains("Hello"));
    assert!(!html_res.full_text.contains("bad"));
}

#[test]
fn document_extract_smoke_text_like_mime_matrix() {
    let cases = [
        ("text/plain", "plain text body"),
        ("text/markdown", "# Title\n\nBody"),
        ("application/json", r#"{"k":"v"}"#),
        ("application/ini", "a=b"),
        ("application/csv", "a,b\n1,2"),
        ("application/yaml", "a: b"),
        ("application/toml", "a = \"b\""),
        ("application/xml", "<root><x>ok</x></root>"),
    ];

    for (mime, body) in cases {
        let result =
            content_extract::extract_document(mime, body.as_bytes()).expect("extract text-like");
        assert!(
            !result.full_text.trim().is_empty(),
            "full text should be non-empty for {mime}"
        );
        assert!(
            !result.excerpt.trim().is_empty(),
            "excerpt should be non-empty for {mime}"
        );
        assert!(!result.needs_ocr, "needs_ocr should be false for {mime}");
        assert!(
            result.page_count.is_none(),
            "page_count should be none for {mime}"
        );
    }
}

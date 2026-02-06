use std::io::Cursor;

use anyhow::{anyhow, Result};
use quick_xml::events::Event;
use quick_xml::Reader;

fn local_name(name: &[u8]) -> &[u8] {
    match name.iter().rposition(|b| *b == b':') {
        Some(idx) => &name[idx + 1..],
        None => name,
    }
}

pub fn extract_docx_text(bytes: &[u8]) -> Result<String> {
    if bytes.is_empty() {
        return Err(anyhow!("missing bytes"));
    }

    let cursor = Cursor::new(bytes);
    let mut zip = zip::ZipArchive::new(cursor).map_err(|e| anyhow!("invalid docx zip: {e}"))?;

    let mut file = zip
        .by_name("word/document.xml")
        .map_err(|_| anyhow!("docx missing word/document.xml"))?;

    let mut xml = String::new();
    use std::io::Read as _;
    file.read_to_string(&mut xml)
        .map_err(|e| anyhow!("docx document.xml read failed: {e}"))?;

    let mut reader = Reader::from_str(&xml);
    reader.trim_text(false);

    let mut buf = Vec::<u8>::new();
    let mut out = String::new();

    // Best-effort paragraph separation.
    let mut at_paragraph_start = true;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                if name == b"p" {
                    if !out.is_empty() && !out.ends_with('\n') {
                        out.push('\n');
                    }
                    at_paragraph_start = true;
                } else if name == b"br" {
                    if !out.ends_with('\n') {
                        out.push('\n');
                    }
                    at_paragraph_start = true;
                } else if name == b"tab" {
                    if !out.ends_with(' ') && !out.ends_with('\n') {
                        out.push(' ');
                    }
                }
            }
            Ok(Event::Text(e)) => {
                let text = e
                    .unescape()
                    .map_err(|e| anyhow!("docx xml unescape failed: {e}"))?;
                let t = text.as_ref();
                if t.is_empty() {
                    // no-op
                } else {
                    if at_paragraph_start {
                        // Avoid leading indentation.
                        out.push_str(t.trim_start());
                    } else {
                        out.push_str(t);
                    }
                    at_paragraph_start = false;
                }
            }
            Ok(Event::End(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                if name == b"p" {
                    if !out.is_empty() && !out.ends_with('\n') {
                        out.push('\n');
                    }
                    at_paragraph_start = true;
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(anyhow!("docx xml parse failed: {e}")),
            _ => {}
        }
        buf.clear();
    }

    Ok(out)
}

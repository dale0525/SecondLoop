use anyhow::{anyhow, Result};

mod docx;
mod pdf;

const MAX_FULL_TEXT_BYTES: usize = 256 * 1024;
const MAX_EXCERPT_TEXT_BYTES: usize = 8 * 1024;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DocumentExtractResult {
    pub full_text: String,
    pub excerpt: String,
    pub page_count: Option<u32>,
    pub needs_ocr: bool,
}

fn truncate_utf8_to_max_bytes(s: &str, max_bytes: usize) -> &str {
    if s.len() <= max_bytes {
        return s;
    }
    let mut end = max_bytes;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

fn normalize_text_keep_paragraphs(input: &str) -> String {
    let mut out = String::with_capacity(input.len().min(16 * 1024));

    let mut last_was_space = false;
    let mut newline_run = 0usize;

    for ch in input.chars() {
        match ch {
            '\r' => continue,
            '\n' => {
                while out.ends_with(' ') {
                    out.pop();
                }
                if newline_run < 2 {
                    out.push('\n');
                }
                newline_run += 1;
                last_was_space = false;
            }
            c if c.is_whitespace() => {
                // Skip indentation after newlines.
                if newline_run > 0 {
                    continue;
                }
                if out.is_empty() {
                    continue;
                }
                if !last_was_space {
                    out.push(' ');
                    last_was_space = true;
                }
            }
            _ => {
                out.push(ch);
                last_was_space = false;
                newline_run = 0;
            }
        }
    }

    out.trim().to_string()
}

fn decode_html_entities(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut i = 0usize;
    let bytes = input.as_bytes();
    while i < bytes.len() {
        if bytes[i] != b'&' {
            out.push(bytes[i] as char);
            i += 1;
            continue;
        }

        // Find ';'
        let mut j = i + 1;
        while j < bytes.len() && j - i <= 12 && bytes[j] != b';' {
            j += 1;
        }
        if j >= bytes.len() || bytes[j] != b';' {
            out.push('&');
            i += 1;
            continue;
        }

        let entity = &input[i + 1..j];
        let decoded = match entity {
            "amp" => Some("&".to_string()),
            "lt" => Some("<".to_string()),
            "gt" => Some(">".to_string()),
            "quot" => Some("\"".to_string()),
            "apos" => Some("'".to_string()),
            "#39" => Some("'".to_string()),
            "nbsp" => Some(" ".to_string()),
            _ => {
                if let Some(num) = entity
                    .strip_prefix("#x")
                    .or_else(|| entity.strip_prefix("#X"))
                {
                    u32::from_str_radix(num, 16)
                        .ok()
                        .and_then(char::from_u32)
                        .map(|c| c.to_string())
                } else if let Some(num) = entity.strip_prefix('#') {
                    num.parse::<u32>()
                        .ok()
                        .and_then(char::from_u32)
                        .map(|c| c.to_string())
                } else {
                    None
                }
            }
        };

        if let Some(decoded) = decoded {
            out.push_str(&decoded);
        } else {
            out.push('&');
            out.push_str(entity);
            out.push(';');
        }
        i = j + 1;
    }
    out
}

fn strip_tag_blocks_case_insensitive(input: &str, tag: &str) -> String {
    let lower = input.to_lowercase();
    let mut out = String::with_capacity(input.len());

    let open = format!("<{tag}");
    let close = format!("</{tag}");

    let mut i = 0usize;
    while i < input.len() {
        if let Some(pos) = lower[i..].find(&open) {
            let start = i + pos;
            out.push_str(&input[i..start]);

            let after_open = start + open.len();
            if let Some(end_pos) = lower[after_open..].find(&close) {
                let end = after_open + end_pos;
                // Skip to end of close tag '>'
                if let Some(gt) = lower[end..].find('>') {
                    i = end + gt + 1;
                } else {
                    break;
                }
            } else {
                break;
            }
        } else {
            out.push_str(&input[i..]);
            break;
        }
    }

    out
}

fn html_to_text_v1(html: &str) -> String {
    let mut s = html.to_string();
    for tag in ["script", "style", "noscript"] {
        s = strip_tag_blocks_case_insensitive(&s, tag);
    }

    let mut out = String::with_capacity(s.len());
    let mut i = 0usize;
    let bytes = s.as_bytes();

    while i < bytes.len() {
        if bytes[i] != b'<' {
            out.push(bytes[i] as char);
            i += 1;
            continue;
        }

        // Parse tag.
        let mut j = i + 1;
        while j < bytes.len() && bytes[j] != b'>' {
            j += 1;
        }
        if j >= bytes.len() {
            break;
        }

        let raw_tag = &s[i + 1..j];
        let raw_tag = raw_tag.trim();
        let raw_tag = raw_tag.strip_prefix('/').unwrap_or(raw_tag).trim();
        let tag_name = raw_tag
            .split_whitespace()
            .next()
            .unwrap_or("")
            .split(':')
            .last()
            .unwrap_or("")
            .to_ascii_lowercase();

        let is_block = matches!(
            tag_name.as_str(),
            "p" | "div"
                | "li"
                | "h1"
                | "h2"
                | "h3"
                | "h4"
                | "h5"
                | "h6"
                | "br"
                | "hr"
                | "pre"
                | "blockquote"
                | "tr"
                | "td"
                | "th"
                | "section"
                | "article"
        );
        if is_block {
            out.push('\n');
        }

        i = j + 1;
    }

    let decoded = decode_html_entities(&out);
    normalize_text_keep_paragraphs(&decoded)
}

fn is_text_like_mime(mime_type: &str) -> bool {
    let mt = mime_type.trim().to_ascii_lowercase();
    if mt.starts_with("text/") {
        return true;
    }
    matches!(
        mt.as_str(),
        "application/json"
            | "application/xml"
            | "application/xhtml+xml"
            | "application/x-yaml"
            | "application/yaml"
            | "application/toml"
            | "application/x-toml"
            | "application/ini"
            | "application/x-ini"
            | "application/csv"
            | "application/x-csv"
    )
}

/// Extracts a searchable text layer from document-like attachments.
///
/// v1 behavior:
/// - Text-like: UTF-8 decode + whitespace normalization; HTML is stripped to text.
/// - docx: extract `word/document.xml` text, best-effort paragraph newlines.
/// - pdf: extract text; if empty => `needs_ocr=true` (OCR in later milestone).
pub fn extract_document(mime_type: &str, bytes: &[u8]) -> Result<DocumentExtractResult> {
    let mt = mime_type.trim().to_ascii_lowercase();
    if mt.is_empty() {
        return Err(anyhow!("mime_type is required"));
    }

    if mt == "application/pdf" {
        let pdf = pdf::extract_pdf_text(bytes)?;
        let normalized = normalize_text_keep_paragraphs(&pdf.text);
        let full = truncate_utf8_to_max_bytes(&normalized, MAX_FULL_TEXT_BYTES).to_string();
        let excerpt = truncate_utf8_to_max_bytes(&full, MAX_EXCERPT_TEXT_BYTES).to_string();
        let needs_ocr = full.trim().is_empty();
        return Ok(DocumentExtractResult {
            full_text: full,
            excerpt,
            page_count: Some(pdf.page_count),
            needs_ocr,
        });
    }

    if mt == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" {
        let text = docx::extract_docx_text(bytes)?;
        let normalized = normalize_text_keep_paragraphs(&text);
        let full = truncate_utf8_to_max_bytes(&normalized, MAX_FULL_TEXT_BYTES).to_string();
        let excerpt = truncate_utf8_to_max_bytes(&full, MAX_EXCERPT_TEXT_BYTES).to_string();
        return Ok(DocumentExtractResult {
            full_text: full,
            excerpt,
            page_count: None,
            needs_ocr: false,
        });
    }

    if is_text_like_mime(&mt) {
        let raw = String::from_utf8(bytes.to_vec())
            .map_err(|_| anyhow!("document is not valid utf-8"))?;
        let text = if mt == "text/html" || mt == "application/xhtml+xml" {
            html_to_text_v1(&raw)
        } else {
            normalize_text_keep_paragraphs(&raw)
        };
        let full = truncate_utf8_to_max_bytes(&text, MAX_FULL_TEXT_BYTES).to_string();
        let excerpt = truncate_utf8_to_max_bytes(&full, MAX_EXCERPT_TEXT_BYTES).to_string();
        return Ok(DocumentExtractResult {
            full_text: full,
            excerpt,
            page_count: None,
            needs_ocr: false,
        });
    }

    Err(anyhow!("unsupported mime_type: {mime_type}"))
}

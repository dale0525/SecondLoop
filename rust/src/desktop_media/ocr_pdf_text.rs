use anyhow::{anyhow, Result};
use lopdf::content::Content;
use lopdf::{Document, Encoding, Object};
use std::collections::BTreeMap;

pub(super) struct DesktopPdfTextExtractResult {
    pub(super) text: String,
    pub(super) page_count: u32,
    pub(super) processed_pages: u32,
}

pub(super) fn extract_pdf_text_with_limit(
    bytes: &[u8],
    max_pages: u32,
) -> Result<DesktopPdfTextExtractResult> {
    let doc = Document::load_mem(bytes).map_err(|e| anyhow!("invalid pdf: {e}"))?;
    let pages = doc.get_pages();
    let page_count = u32::try_from(pages.len()).unwrap_or(u32::MAX);
    if pages.is_empty() {
        return Ok(DesktopPdfTextExtractResult {
            text: String::new(),
            page_count: 0,
            processed_pages: 0,
        });
    }

    let mut page_numbers: Vec<u32> = pages.keys().cloned().collect();
    page_numbers.sort_unstable();
    let take_count = usize::try_from(max_pages)
        .unwrap_or(usize::MAX)
        .min(page_numbers.len());
    let selected_pages = page_numbers
        .into_iter()
        .take(take_count)
        .collect::<Vec<_>>();

    let mut text = match doc.extract_text(&selected_pages) {
        Ok(text) => text,
        Err(_) => {
            let mut out = String::new();
            for page_number in &selected_pages {
                if let Ok(page_text) = doc.extract_text(&[*page_number]) {
                    if !out.is_empty() && !out.ends_with('\n') {
                        out.push('\n');
                    }
                    out.push_str(&page_text);
                }
            }
            out
        }
    };

    if text.trim().is_empty() {
        if let Ok(fallback_text) =
            extract_text_with_manual_tounicode_fallback(&doc, &selected_pages)
        {
            if !fallback_text.trim().is_empty() {
                text = fallback_text;
            }
        }
    }

    Ok(DesktopPdfTextExtractResult {
        text,
        page_count,
        processed_pages: u32::try_from(selected_pages.len()).unwrap_or(u32::MAX),
    })
}

enum FontDecoder<'a> {
    Lopdf(Encoding<'a>),
    Manual(SimpleToUnicodeMap),
}

#[derive(Default)]
struct SimpleToUnicodeMap {
    source_code_bytes: usize,
    mappings: BTreeMap<u16, Vec<u16>>,
}

impl SimpleToUnicodeMap {
    fn decode_text_bytes(&self, bytes: &[u8]) -> String {
        let mut utf16 = Vec::<u16>::new();

        if self.source_code_bytes == 1 {
            for byte in bytes {
                let code = u16::from(*byte);
                if let Some(mapped) = self.mappings.get(&code) {
                    utf16.extend(mapped);
                }
            }
        } else {
            for chunk in bytes.chunks_exact(2) {
                let code = u16::from_be_bytes([chunk[0], chunk[1]]);
                if let Some(mapped) = self.mappings.get(&code) {
                    utf16.extend(mapped);
                }
            }
        }

        String::from_utf16_lossy(&utf16)
    }
}

fn extract_text_with_manual_tounicode_fallback(
    doc: &Document,
    selected_pages: &[u32],
) -> Result<String> {
    let pages = doc.get_pages();
    let mut out = String::new();

    for page_number in selected_pages {
        let Some(page_id) = pages.get(page_number).copied() else {
            continue;
        };

        let decoders = build_page_font_decoders(doc, page_id)?;
        let content_data = doc.get_page_content(page_id)?;
        let content = Content::decode(&content_data)?;
        let mut current_font_decoder: Option<&FontDecoder<'_>> = None;

        for operation in &content.operations {
            match operation.operator.as_str() {
                "Tf" => {
                    let current_font = operation
                        .operands
                        .first()
                        .and_then(|operand| operand.as_name().ok());
                    current_font_decoder =
                        current_font.and_then(|font_name| decoders.get(font_name));
                }
                "Tj" | "TJ" => {
                    if let Some(decoder) = current_font_decoder {
                        collect_text_with_decoder(&mut out, decoder, &operation.operands);
                    }
                }
                "ET" => {
                    if !out.ends_with('\n') {
                        out.push('\n');
                    }
                }
                _ => {}
            }
        }
    }

    Ok(out)
}

fn build_page_font_decoders(
    doc: &Document,
    page_id: lopdf::ObjectId,
) -> Result<BTreeMap<Vec<u8>, FontDecoder<'_>>> {
    let fonts = doc.get_page_fonts(page_id)?;
    let mut decoders = BTreeMap::<Vec<u8>, FontDecoder<'_>>::new();

    for (name, font) in fonts {
        if let Ok(encoding) = font.get_font_encoding(doc) {
            decoders.insert(name.clone(), FontDecoder::Lopdf(encoding));
            continue;
        }

        let to_unicode = font
            .get_deref(b"ToUnicode", doc)
            .and_then(Object::as_stream)
            .and_then(|stream| stream.get_plain_content())
            .ok();
        let Some(to_unicode) = to_unicode else {
            continue;
        };

        if let Some(map) = parse_simple_tounicode_cmap(&to_unicode) {
            decoders.insert(name.clone(), FontDecoder::Manual(map));
        }
    }

    Ok(decoders)
}

fn collect_text_with_decoder(text: &mut String, decoder: &FontDecoder<'_>, operands: &[Object]) {
    for operand in operands {
        match operand {
            Object::String(bytes, _) => match decoder {
                FontDecoder::Lopdf(encoding) => {
                    if let Ok(piece) = Document::decode_text(encoding, bytes) {
                        text.push_str(&piece);
                    }
                }
                FontDecoder::Manual(map) => text.push_str(&map.decode_text_bytes(bytes)),
            },
            Object::Array(arr) => {
                collect_text_with_decoder(text, decoder, arr);
                text.push(' ');
            }
            Object::Integer(i) => {
                if *i < -100 {
                    text.push(' ');
                }
            }
            _ => {}
        }
    }
}

fn parse_simple_tounicode_cmap(content: &[u8]) -> Option<SimpleToUnicodeMap> {
    let raw = String::from_utf8_lossy(content);
    let mut map = SimpleToUnicodeMap {
        source_code_bytes: 2,
        mappings: BTreeMap::new(),
    };

    #[derive(Clone, Copy)]
    enum Section {
        None,
        CodeSpace,
        BfChar,
        BfRange,
    }

    let mut section = Section::None;

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if trimmed.ends_with("begincodespacerange") {
            section = Section::CodeSpace;
            continue;
        }
        if trimmed.ends_with("beginbfchar") {
            section = Section::BfChar;
            continue;
        }
        if trimmed.ends_with("beginbfrange") {
            section = Section::BfRange;
            continue;
        }
        if trimmed.starts_with("endcodespacerange")
            || trimmed.starts_with("endbfchar")
            || trimmed.starts_with("endbfrange")
        {
            section = Section::None;
            continue;
        }

        let hex_strings = extract_hex_strings(trimmed);
        if hex_strings.is_empty() {
            continue;
        }

        match section {
            Section::CodeSpace => {
                if let Some(src) = hex_strings.first() {
                    let code_bytes = src.len() / 2;
                    if code_bytes == 1 || code_bytes == 2 {
                        map.source_code_bytes = code_bytes;
                    }
                }
            }
            Section::BfChar => {
                if hex_strings.len() < 2 {
                    continue;
                }
                let Some(src) = parse_source_code(hex_strings[0]) else {
                    continue;
                };
                let Some(dst) = parse_utf16_hex_string(hex_strings[1]) else {
                    continue;
                };
                map.mappings.insert(src, dst);
            }
            Section::BfRange => {
                if hex_strings.len() < 3 {
                    continue;
                }
                let Some(src_start) = parse_source_code(hex_strings[0]) else {
                    continue;
                };
                let Some(src_end) = parse_source_code(hex_strings[1]) else {
                    continue;
                };
                if src_end < src_start {
                    continue;
                }

                if trimmed.contains('[') {
                    for (offset, dst_hex) in hex_strings.iter().skip(2).enumerate() {
                        let code =
                            src_start.saturating_add(u16::try_from(offset).unwrap_or(u16::MAX));
                        if code > src_end {
                            break;
                        }
                        let Some(dst) = parse_utf16_hex_string(dst_hex) else {
                            continue;
                        };
                        map.mappings.insert(code, dst);
                    }
                    continue;
                }

                let Some(base_dst) = parse_utf16_hex_string(hex_strings[2]) else {
                    continue;
                };
                for code in src_start..=src_end {
                    let offset = code - src_start;
                    let mapped = increment_utf16_mapping(&base_dst, offset);
                    map.mappings.insert(code, mapped);
                }
            }
            Section::None => {}
        }
    }

    if map.mappings.is_empty() {
        return None;
    }
    Some(map)
}

fn extract_hex_strings(line: &str) -> Vec<&str> {
    let mut out = Vec::<&str>::new();
    let mut start: Option<usize> = None;

    for (index, ch) in line.char_indices() {
        if ch == '<' {
            start = Some(index + 1);
            continue;
        }
        if ch == '>' {
            if let Some(begin) = start {
                let segment = &line[begin..index];
                if !segment.is_empty() {
                    out.push(segment);
                }
            }
            start = None;
        }
    }

    out
}

fn parse_source_code(hex: &str) -> Option<u16> {
    if hex.len() != 2 && hex.len() != 4 {
        return None;
    }
    u16::from_str_radix(hex, 16).ok()
}

fn parse_utf16_hex_string(hex: &str) -> Option<Vec<u16>> {
    if hex.len() < 4 || !hex.as_bytes().chunks_exact(4).remainder().is_empty() {
        return None;
    }

    let mut out = Vec::<u16>::new();
    for chunk in hex.as_bytes().chunks_exact(4) {
        let chunk_str = std::str::from_utf8(chunk).ok()?;
        out.push(u16::from_str_radix(chunk_str, 16).ok()?);
    }
    Some(out)
}

fn increment_utf16_mapping(base: &[u16], offset: u16) -> Vec<u16> {
    if base.is_empty() {
        return Vec::new();
    }

    let mut out = base.to_vec();
    if let Some(last) = out.last_mut() {
        *last = last.wrapping_add(offset);
    }
    out
}

use anyhow::{anyhow, Result};
use lopdf::Document;

pub struct PdfTextExtractResult {
    pub text: String,
    pub page_count: u32,
}

pub fn extract_pdf_text(bytes: &[u8]) -> Result<PdfTextExtractResult> {
    if bytes.is_empty() {
        return Err(anyhow!("missing bytes"));
    }

    let doc = Document::load_mem(bytes).map_err(|e| anyhow!("invalid pdf: {e}"))?;
    let pages = doc.get_pages();
    let page_count = u32::try_from(pages.len()).unwrap_or(u32::MAX);

    if pages.is_empty() {
        return Ok(PdfTextExtractResult {
            text: String::new(),
            page_count: 0,
        });
    }

    let mut page_numbers: Vec<u32> = pages.keys().cloned().collect();
    page_numbers.sort_unstable();

    // Prefer lopdf's built-in text extraction.
    let text = match doc.extract_text(&page_numbers) {
        Ok(t) => t,
        Err(_) => {
            let mut out = String::new();
            for n in &page_numbers {
                if let Ok(t) = doc.extract_text(&[*n]) {
                    if !out.is_empty() && !out.ends_with('\n') {
                        out.push('\n');
                    }
                    out.push_str(&t);
                }
            }
            out
        }
    };

    Ok(PdfTextExtractResult { text, page_count })
}

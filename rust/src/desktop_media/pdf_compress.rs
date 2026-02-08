use anyhow::Result;
use lopdf::Document;

pub fn desktop_compress_pdf_scan(bytes: &[u8], _scan_dpi: u32) -> Result<Option<Vec<u8>>> {
    if bytes.is_empty() {
        return Ok(None);
    }

    let mut doc = match Document::load_mem(bytes) {
        Ok(doc) => doc,
        Err(_) => return Ok(None),
    };
    doc.compress();

    let mut out = Vec::with_capacity(bytes.len());
    if doc.save_to(&mut out).is_err() {
        return Ok(None);
    }
    if out.is_empty() || out.len() >= bytes.len() {
        return Ok(None);
    }
    Ok(Some(out))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_pdf_returns_none() {
        let compressed = desktop_compress_pdf_scan(&[], 180).unwrap();
        assert!(compressed.is_none());
    }
}

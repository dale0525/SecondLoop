use anyhow::Result;

use crate::desktop_media;

#[flutter_rust_bridge::frb]
pub fn desktop_ocr_image(
    bytes: Vec<u8>,
    language_hints: String,
) -> Result<desktop_media::ocr::OcrPayload> {
    desktop_media::ocr::desktop_ocr_image(&bytes, &language_hints)
}

#[flutter_rust_bridge::frb]
pub fn desktop_ocr_pdf(
    bytes: Vec<u8>,
    max_pages: u32,
    dpi: u32,
    language_hints: String,
) -> Result<desktop_media::ocr::OcrPayload> {
    desktop_media::ocr::desktop_ocr_pdf(&bytes, max_pages, dpi, &language_hints)
}

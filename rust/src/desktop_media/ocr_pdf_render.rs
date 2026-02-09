use anyhow::{anyhow, Result};
use base64::prelude::*;
use image::RgbImage;
use lopdf::Document;

use super::super::pdf_page_image_decode::{
    collect_page_image_candidates, decode_pdf_image_to_rgb_with_reason, PdfImageCandidate,
};
#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
use super::ocr_pdf_text::extract_pdf_text_with_limit;
use super::OcrPayload;

pub const PDF_RENDER_MODE_HINT: &str = "__secondloop_render_long_image_jpeg__";

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const PDF_RENDER_MAX_OUTPUT_WIDTH: u32 = 1536;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const PDF_RENDER_MAX_OUTPUT_HEIGHT: u32 = 20_000;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const PDF_RENDER_MAX_OUTPUT_PIXELS: u64 = 20_000_000;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const PDF_RENDER_JPEG_QUALITY: u8 = 82;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_MAX_IMAGE_CANDIDATES_PER_PAGE: usize = 8;

fn truncate_utf8(input: &str, max_bytes: usize) -> String {
    if input.len() <= max_bytes {
        return input.to_string();
    }
    let mut end = max_bytes;
    while end > 0 && !input.is_char_boundary(end) {
        end -= 1;
    }
    input[..end].to_string()
}

fn build_payload(
    text: &str,
    page_count: u32,
    processed_pages: u32,
    engine: &str,
    force_truncated: bool,
) -> OcrPayload {
    let full = truncate_utf8(text, 256 * 1024);
    let excerpt = truncate_utf8(&full, 8 * 1024);
    let is_truncated = force_truncated || full != text || processed_pages < page_count;
    OcrPayload {
        ocr_text_full: full,
        ocr_text_excerpt: excerpt,
        ocr_engine: engine.to_string(),
        ocr_is_truncated: is_truncated,
        ocr_page_count: page_count,
        ocr_processed_pages: processed_pages,
    }
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub fn render_pdf_to_long_image_payload(
    bytes: &[u8],
    max_pages: u32,
    dpi: u32,
) -> Result<OcrPayload> {
    let safe_max_pages = max_pages.clamp(1, 10_000);
    let safe_dpi = dpi.clamp(72, 600);
    let doc = Document::load_mem(bytes).map_err(|e| anyhow!("invalid pdf: {e}"))?;
    let pages = doc.get_pages();
    if pages.is_empty() {
        return Ok(build_payload(
            "",
            0,
            0,
            "desktop_rust_pdf_render_empty",
            false,
        ));
    }

    let page_count = pages.len().min(u32::MAX as usize) as u32;
    let mut page_numbers: Vec<u32> = pages.keys().cloned().collect();
    page_numbers.sort_unstable();
    let take_count = usize::try_from(safe_max_pages)
        .unwrap_or(usize::MAX)
        .min(page_numbers.len());

    let mut rendered_images: Vec<RgbImage> = Vec::new();
    let mut output_width: u32 = 0;
    let mut output_height: u32 = 0;
    let mut processed_pages: u32 = 0;

    for page_number in page_numbers.into_iter().take(take_count) {
        let Some(page_id) = pages.get(&page_number).copied() else {
            continue;
        };
        let mut image_candidates = collect_page_image_candidates(&doc, page_id);
        if image_candidates.is_empty() {
            continue;
        }

        image_candidates.sort_by(|a, b| {
            let area_a = i128::from(a.width).saturating_mul(i128::from(a.height));
            let area_b = i128::from(b.width).saturating_mul(i128::from(b.height));
            area_b.cmp(&area_a)
        });

        let mut picked: Option<RgbImage> = None;
        for candidate in image_candidates
            .into_iter()
            .take(OCR_MAX_IMAGE_CANDIDATES_PER_PAGE)
        {
            if let Ok(rgb) = decode_pdf_image_to_rgb_with_reason(
                &doc,
                PdfImageCandidate {
                    object_id: candidate.object_id,
                    width: candidate.width,
                    height: candidate.height,
                },
            ) {
                picked = Some(rgb);
                break;
            }
        }

        let Some(mut image) = picked else {
            continue;
        };

        let max_width = PDF_RENDER_MAX_OUTPUT_WIDTH;
        if image.width() > max_width {
            let src_w = image.width();
            let src_h = image.height().max(1);
            let scaled_h = ((u64::from(src_h) * u64::from(max_width)) / u64::from(src_w))
                .max(1)
                .min(u64::from(u32::MAX)) as u32;
            image = image::imageops::resize(
                &image,
                max_width,
                scaled_h,
                image::imageops::FilterType::Triangle,
            );
        }

        let dpi_scale = safe_dpi as f32 / 180.0f32;
        if (dpi_scale - 1.0).abs() > f32::EPSILON {
            let target_w = (image.width() as f32 * dpi_scale).round().max(1.0) as u32;
            let target_h = (image.height() as f32 * dpi_scale).round().max(1.0) as u32;
            if target_w > 0 && target_h > 0 {
                image = image::imageops::resize(
                    &image,
                    target_w,
                    target_h,
                    image::imageops::FilterType::Triangle,
                );
            }
        }

        let next_width = output_width.max(image.width());
        let next_height = output_height.saturating_add(image.height());
        if next_height > PDF_RENDER_MAX_OUTPUT_HEIGHT {
            break;
        }
        let next_pixels = u64::from(next_width).saturating_mul(u64::from(next_height));
        if next_pixels > PDF_RENDER_MAX_OUTPUT_PIXELS {
            break;
        }

        output_width = next_width;
        output_height = next_height;
        rendered_images.push(image);
        processed_pages = processed_pages.saturating_add(1);
    }

    if rendered_images.is_empty() || output_width == 0 || output_height == 0 {
        return Ok(build_payload(
            "",
            page_count,
            processed_pages,
            "desktop_rust_pdf_render_empty",
            false,
        ));
    }

    let mut canvas = RgbImage::from_pixel(
        output_width,
        output_height,
        image::Rgb::<u8>([255, 255, 255]),
    );
    let mut y: u32 = 0;
    for image in rendered_images {
        image::imageops::overlay(&mut canvas, &image, 0, i64::from(y));
        y = y.saturating_add(image.height());
    }

    let mut encoded = Vec::<u8>::new();
    let mut encoder =
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut encoded, PDF_RENDER_JPEG_QUALITY);
    encoder
        .encode_image(&image::DynamicImage::ImageRgb8(canvas))
        .map_err(|e| anyhow!("encode jpeg failed: {e}"))?;

    let b64 = BASE64_STANDARD.encode(&encoded);
    Ok(build_payload(
        &b64,
        page_count,
        processed_pages,
        "desktop_rust_pdf_render_jpeg",
        false,
    ))
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
pub fn render_pdf_to_long_image_payload(
    bytes: &[u8],
    max_pages: u32,
    _dpi: u32,
) -> Result<OcrPayload> {
    let safe_max_pages = max_pages.clamp(1, 10_000);
    let extracted = extract_pdf_text_with_limit(bytes, safe_max_pages)?;
    Ok(build_payload(
        "",
        extracted.page_count,
        extracted.processed_pages,
        "desktop_rust_pdf_render_unsupported",
        false,
    ))
}

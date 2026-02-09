use anyhow::{anyhow, Result};
use lopdf::Document;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[path = "ocr_model_config.rs"]
mod ocr_model_config;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[path = "ocr_parallel.rs"]
mod ocr_parallel;
#[path = "ocr_pdf_render.rs"]
mod ocr_pdf_render;
#[path = "ocr_pdf_text.rs"]
mod ocr_pdf_text;

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use super::pdf_page_image_decode::{
    collect_page_image_candidates, decode_pdf_image_to_rgb_with_reason, PdfImageCandidate,
    PdfImageDecodeFailureReason,
};
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use image::RgbImage;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use ocr_model_config::resolve_ocr_model_config;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use ocr_parallel::choose_ocr_page_worker_count;
use ocr_pdf_render::{render_pdf_to_long_image_payload, PDF_RENDER_MODE_HINT};
use ocr_pdf_text::extract_pdf_text_with_limit;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use paddle_ocr_rs::ocr_lite::OcrLite;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use std::collections::HashMap;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use std::sync::{Arc, Condvar, Mutex, OnceLock};

const MAX_FULL_TEXT_BYTES: usize = 256 * 1024;
const MAX_EXCERPT_TEXT_BYTES: usize = 8 * 1024;
const OCR_MODEL_DIR_ENV: &str = "SECONDLOOP_OCR_MODEL_DIR";

const DET_MODEL_ALIASES: [&str; 3] = [
    "ch_PP-OCRv5_mobile_det.onnx",
    "ch_PP-OCRv4_det_infer.onnx",
    "ch_PP-OCRv3_det_infer.onnx",
];
const CLS_MODEL_ALIASES: [&str; 1] = ["ch_ppocr_mobile_v2.0_cls_infer.onnx"];

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_PADDING: u32 = 50;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_BOX_SCORE_THRESH: f32 = 0.5;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_BOX_THRESH: f32 = 0.3;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_UNCLIP_RATIO: f32 = 1.6;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_TEXT_SCORE_THRESH: f32 = 0.5;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_MAX_SIDE_LEN: u32 = 1152;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_MAX_IMAGE_CANDIDATES_PER_PAGE: usize = 8;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const OCR_PRIMARY_ORIENTATION_MIN_CHARS: usize = 30;

#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct OcrPayload {
    pub ocr_text_full: String,
    pub ocr_text_excerpt: String,
    pub ocr_engine: String,
    pub ocr_is_truncated: bool,
    pub ocr_page_count: u32,
    pub ocr_processed_pages: u32,
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
struct PdfImageOcrFallbackResult {
    text: String,
    model_available: bool,
    image_candidate_count: u32,
    decoded_image_count: u32,
    decode_unsupported_color_space_count: u32,
    decode_unsupported_bits_per_component_count: u32,
    decode_other_failure_count: u32,
    ocr_attempt_count: u32,
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[derive(Clone, Debug, Default)]
struct OcrTextResult {
    text: String,
    avg_line_score: f32,
    char_count: usize,
    quality_score: f32,
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[derive(Default)]
struct OcrPageWorkerResult {
    page_texts: Vec<(usize, String)>,
    ocr_attempt_count: usize,
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[derive(Clone, Copy)]
struct RecModelSpec {
    key: &'static str,
    model_files: &'static [&'static str],
    dict_files: &'static [&'static str],
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const REC_MODEL_SPECS: &[RecModelSpec] = &[
    RecModelSpec {
        key: "zh_hans",
        model_files: &[
            "ch_PP-OCRv5_rec_mobile_infer.onnx",
            "ch_PP-OCRv5_mobile_rec.onnx",
            "ch_PP-OCRv4_rec_infer.onnx",
            "ch_PP-OCRv3_rec_infer.onnx",
        ],
        dict_files: &[],
    },
    RecModelSpec {
        key: "latin",
        model_files: &["latin_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["latin_dict.txt"],
    },
    RecModelSpec {
        key: "arabic",
        model_files: &["arabic_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["arabic_dict.txt"],
    },
    RecModelSpec {
        key: "cyrillic",
        model_files: &["cyrillic_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["cyrillic_dict.txt"],
    },
    RecModelSpec {
        key: "devanagari",
        model_files: &["devanagari_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["devanagari_dict.txt"],
    },
    RecModelSpec {
        key: "ja",
        model_files: &["japan_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["japan_dict.txt"],
    },
    RecModelSpec {
        key: "ko",
        model_files: &["korean_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["korean_dict.txt"],
    },
    RecModelSpec {
        key: "zh_hant",
        model_files: &["chinese_cht_PP-OCRv3_rec_infer.onnx"],
        dict_files: &["chinese_cht_dict.txt"],
    },
];

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[derive(Clone)]
struct ResolvedOcrModelConfig {
    det_path: PathBuf,
    cls_path: PathBuf,
    rec_path: PathBuf,
    dict_path: Option<PathBuf>,
    cache_key: String,
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub fn desktop_ocr_image(bytes: &[u8], language_hints: &str) -> Result<OcrPayload> {
    if bytes.is_empty() {
        return Err(anyhow!("missing image bytes"));
    }

    let image = image::load_from_memory(bytes)
        .map_err(|e| anyhow!("invalid image bytes: {e}"))?
        .to_rgb8();

    let text = ocr_image_text(&image, language_hints, None)?;
    if text.is_empty() {
        return Ok(build_payload(
            "",
            1,
            1,
            "desktop_rust_image_no_model",
            false,
        ));
    }

    Ok(build_payload(&text, 1, 1, "desktop_rust_image_onnx", false))
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
pub fn desktop_ocr_image(bytes: &[u8], _language_hints: &str) -> Result<OcrPayload> {
    if bytes.is_empty() {
        return Err(anyhow!("missing image bytes"));
    }
    Ok(build_payload(
        "",
        1,
        1,
        "desktop_rust_image_unsupported",
        false,
    ))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub fn desktop_ocr_pdf(
    bytes: &[u8],
    max_pages: u32,
    dpi: u32,
    language_hints: &str,
) -> Result<OcrPayload> {
    if bytes.is_empty() {
        return Err(anyhow!("missing pdf bytes"));
    }

    if language_hints.trim() == PDF_RENDER_MODE_HINT {
        return render_pdf_to_long_image_payload(bytes, max_pages, dpi);
    }

    let safe_max_pages = max_pages.clamp(1, 10_000);
    let extracted = extract_pdf_text_with_limit(bytes, safe_max_pages)?;
    let text = normalize_text_keep_paragraphs(&extracted.text);
    if !text.is_empty() {
        return Ok(build_payload(
            &text,
            extracted.page_count,
            extracted.processed_pages,
            "desktop_rust_pdf_text",
            false,
        ));
    }

    let fallback = ocr_pdf_page_images(bytes, safe_max_pages, language_hints, None)?;
    if !fallback.text.is_empty() {
        return Ok(build_payload(
            &fallback.text,
            extracted.page_count,
            extracted.processed_pages,
            "desktop_rust_pdf_onnx",
            false,
        ));
    }

    let empty_engine = if !fallback.model_available {
        "desktop_rust_pdf_no_model"
    } else if fallback.image_candidate_count == 0 {
        "desktop_rust_pdf_no_image_candidates"
    } else if fallback.decoded_image_count == 0 {
        if fallback.decode_unsupported_color_space_count > 0 {
            "desktop_rust_pdf_image_decode_unsupported_colorspace"
        } else if fallback.decode_unsupported_bits_per_component_count > 0 {
            "desktop_rust_pdf_image_decode_unsupported_bpc"
        } else if fallback.decode_other_failure_count > 0 {
            "desktop_rust_pdf_image_decode_failed"
        } else {
            "desktop_rust_pdf_image_decode_empty"
        }
    } else if fallback.ocr_attempt_count == 0 {
        "desktop_rust_pdf_onnx_not_attempted"
    } else {
        "desktop_rust_pdf_onnx_empty"
    };

    Ok(build_payload(
        "",
        extracted.page_count,
        extracted.processed_pages,
        empty_engine,
        false,
    ))
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
pub fn desktop_ocr_pdf(
    bytes: &[u8],
    max_pages: u32,
    dpi: u32,
    _language_hints: &str,
) -> Result<OcrPayload> {
    if bytes.is_empty() {
        return Err(anyhow!("missing pdf bytes"));
    }

    if _language_hints.trim() == PDF_RENDER_MODE_HINT {
        return render_pdf_to_long_image_payload(bytes, max_pages, dpi);
    }

    let safe_max_pages = max_pages.clamp(1, 10_000);
    let extracted = extract_pdf_text_with_limit(bytes, safe_max_pages)?;
    Ok(build_payload(
        &normalize_text_keep_paragraphs(&extracted.text),
        extracted.page_count,
        extracted.processed_pages,
        "desktop_rust_pdf_text",
        false,
    ))
}

fn build_payload(
    text: &str,
    page_count: u32,
    processed_pages: u32,
    engine: &str,
    force_truncated: bool,
) -> OcrPayload {
    let full = truncate_utf8(text, MAX_FULL_TEXT_BYTES);
    let excerpt = truncate_utf8(&full, MAX_EXCERPT_TEXT_BYTES);
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
                if newline_run > 0 || out.is_empty() {
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

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn ocr_image_text(
    image: &RgbImage,
    language_hints: &str,
    model_dir: Option<&str>,
) -> Result<String> {
    let Some(config) = resolve_ocr_model_config(language_hints, model_dir) else {
        return Ok(String::new());
    };
    let result = run_ocr_with_cached_model(&config, image, None)?;
    Ok(result.text)
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn ocr_pdf_page_images(
    bytes: &[u8],
    max_pages: u32,
    language_hints: &str,
    model_dir: Option<&str>,
) -> Result<PdfImageOcrFallbackResult> {
    let Some(config) = resolve_ocr_model_config(language_hints, model_dir) else {
        return Ok(PdfImageOcrFallbackResult {
            text: String::new(),
            model_available: false,
            image_candidate_count: 0,
            decoded_image_count: 0,
            decode_unsupported_color_space_count: 0,
            decode_unsupported_bits_per_component_count: 0,
            decode_other_failure_count: 0,
            ocr_attempt_count: 0,
        });
    };

    let doc = Document::load_mem(bytes).map_err(|e| anyhow!("invalid pdf: {e}"))?;
    let pages = doc.get_pages();
    if pages.is_empty() {
        return Ok(PdfImageOcrFallbackResult {
            text: String::new(),
            model_available: true,
            image_candidate_count: 0,
            decoded_image_count: 0,
            decode_unsupported_color_space_count: 0,
            decode_unsupported_bits_per_component_count: 0,
            decode_other_failure_count: 0,
            ocr_attempt_count: 0,
        });
    }

    let mut page_numbers: Vec<u32> = pages.keys().cloned().collect();
    page_numbers.sort_unstable();
    let take_count = usize::try_from(max_pages)
        .unwrap_or(usize::MAX)
        .min(page_numbers.len());
    let selected_page_numbers = page_numbers
        .into_iter()
        .take(take_count)
        .collect::<Vec<_>>();

    let mut decoded_pages = Vec::<Vec<RgbImage>>::with_capacity(selected_page_numbers.len());
    let mut image_candidate_count = 0usize;
    let mut decoded_image_count = 0usize;
    let mut decode_unsupported_color_space_count = 0usize;
    let mut decode_unsupported_bits_per_component_count = 0usize;
    let mut decode_other_failure_count = 0usize;
    let mut ocr_attempt_count = 0usize;
    for page_number in selected_page_numbers {
        let Some(page_id) = pages.get(&page_number).copied() else {
            decoded_pages.push(Vec::new());
            continue;
        };

        let mut image_candidates = collect_page_image_candidates(&doc, page_id);
        if image_candidates.is_empty() {
            decoded_pages.push(Vec::new());
            continue;
        }
        image_candidate_count = image_candidate_count.saturating_add(image_candidates.len());

        image_candidates.sort_by(|a, b| {
            let area_a = i128::from(a.width).saturating_mul(i128::from(a.height));
            let area_b = i128::from(b.width).saturating_mul(i128::from(b.height));
            area_b.cmp(&area_a)
        });

        let mut decoded_images = Vec::<RgbImage>::new();
        for candidate in image_candidates
            .into_iter()
            .take(OCR_MAX_IMAGE_CANDIDATES_PER_PAGE)
        {
            match decode_pdf_image_to_rgb_with_reason(
                &doc,
                PdfImageCandidate {
                    object_id: candidate.object_id,
                    width: candidate.width,
                    height: candidate.height,
                },
            ) {
                Ok(rgb) => {
                    decoded_image_count = decoded_image_count.saturating_add(1);
                    decoded_images.push(rgb);
                }
                Err(PdfImageDecodeFailureReason::UnsupportedColorSpace) => {
                    decode_unsupported_color_space_count =
                        decode_unsupported_color_space_count.saturating_add(1);
                }
                Err(PdfImageDecodeFailureReason::UnsupportedBitsPerComponent) => {
                    decode_unsupported_bits_per_component_count =
                        decode_unsupported_bits_per_component_count.saturating_add(1);
                }
                Err(_) => {
                    decode_other_failure_count = decode_other_failure_count.saturating_add(1);
                }
            }
        }
        decoded_pages.push(decoded_images);
    }

    let pages_with_images = decoded_pages
        .iter()
        .filter(|images| !images.is_empty())
        .count();
    let mut page_text_by_index = vec![String::new(); decoded_pages.len()];
    let available_parallelism = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1);
    let worker_count = choose_ocr_page_worker_count(pages_with_images, available_parallelism);

    if worker_count <= 1 {
        for (index, images) in decoded_pages.iter().enumerate() {
            if images.is_empty() {
                continue;
            }
            let (text, attempts) = ocr_decoded_page_images(&config, images, None)?;
            ocr_attempt_count = ocr_attempt_count.saturating_add(attempts);
            if let Some(text) = text {
                page_text_by_index[index] = text;
            }
        }
    } else {
        let worker_results = std::thread::scope(|scope| -> Result<Vec<OcrPageWorkerResult>> {
            let mut handles = Vec::with_capacity(worker_count);
            for worker_id in 0..worker_count {
                let worker_config = config.clone();
                let decoded_pages_ref = &decoded_pages;
                handles.push(scope.spawn(move || -> Result<OcrPageWorkerResult> {
                    let mut out = OcrPageWorkerResult::default();
                    for (index, images) in decoded_pages_ref.iter().enumerate() {
                        if images.is_empty() || (index % worker_count) != worker_id {
                            continue;
                        }
                        let (text, attempts) =
                            ocr_decoded_page_images(&worker_config, images, Some(worker_id))?;
                        out.ocr_attempt_count = out.ocr_attempt_count.saturating_add(attempts);
                        if let Some(text) = text {
                            out.page_texts.push((index, text));
                        }
                    }
                    Ok(out)
                }));
            }

            let mut out = Vec::with_capacity(handles.len());
            for handle in handles {
                let worker = match handle.join() {
                    Ok(result) => result?,
                    Err(payload) => {
                        return Err(anyhow!(
                            "ocr worker panicked: {}",
                            panic_payload_to_string(&*payload)
                        ));
                    }
                };
                out.push(worker);
            }
            Ok(out)
        })?;

        for worker in worker_results {
            ocr_attempt_count = ocr_attempt_count.saturating_add(worker.ocr_attempt_count);
            for (index, text) in worker.page_texts {
                page_text_by_index[index] = text;
            }
        }
    }

    let page_texts = page_text_by_index
        .into_iter()
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>();

    Ok(PdfImageOcrFallbackResult {
        text: normalize_text_keep_paragraphs(&page_texts.join("\n")),
        model_available: true,
        image_candidate_count: u32::try_from(image_candidate_count).unwrap_or(u32::MAX),
        decoded_image_count: u32::try_from(decoded_image_count).unwrap_or(u32::MAX),
        decode_unsupported_color_space_count: u32::try_from(decode_unsupported_color_space_count)
            .unwrap_or(u32::MAX),
        decode_unsupported_bits_per_component_count: u32::try_from(
            decode_unsupported_bits_per_component_count,
        )
        .unwrap_or(u32::MAX),
        decode_other_failure_count: u32::try_from(decode_other_failure_count).unwrap_or(u32::MAX),
        ocr_attempt_count: u32::try_from(ocr_attempt_count).unwrap_or(u32::MAX),
    })
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn run_ocr_with_cached_model(
    config: &ResolvedOcrModelConfig,
    image: &RgbImage,
    cache_slot: Option<usize>,
) -> Result<OcrTextResult> {
    ensure_ocr_onnxruntime_loaded(config)?;

    let cache_key = cache_slot
        .map(|slot| format!("{}|slot:{slot}", config.cache_key))
        .unwrap_or_else(|| config.cache_key.clone());

    let ocr_handle = {
        let cache = ocr_cache();
        let mut guard = match cache.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };

        if !guard.contains_key(&cache_key) {
            let mut ocr = OcrLite::new();
            init_ocr_model(&mut ocr, config)?;
            guard.insert(cache_key.clone(), Arc::new(Mutex::new(ocr)));
        }

        guard
            .get(&cache_key)
            .cloned()
            .ok_or_else(|| anyhow!("ocr model cache unavailable"))?
    };

    let mut ocr_guard = match ocr_handle.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    let ocr = &mut *ocr_guard;

    let max_side_len = image
        .width()
        .max(image.height())
        .clamp(1024, OCR_MAX_SIDE_LEN);
    let primary = ocr
        .detect(
            image,
            OCR_PADDING,
            max_side_len,
            OCR_BOX_SCORE_THRESH,
            OCR_BOX_THRESH,
            OCR_UNCLIP_RATIO,
            true,
            false,
        )
        .map_err(|e| anyhow!("paddle detect failed: {e}"))?;
    let mut best = build_ocr_text_result(primary);
    if should_accept_primary_orientation(&best) {
        return Ok(best);
    }

    let orientations = [
        image::imageops::rotate90(image),
        image::imageops::rotate270(image),
    ];
    for oriented in orientations {
        let rotated = ocr
            .detect(
                &oriented,
                OCR_PADDING,
                max_side_len,
                OCR_BOX_SCORE_THRESH,
                OCR_BOX_THRESH,
                OCR_UNCLIP_RATIO,
                true,
                false,
            )
            .map_err(|e| anyhow!("paddle detect failed: {e}"))?;
        let candidate = build_ocr_text_result(rotated);
        if is_better_ocr_text_result(&candidate, Some(&best)) {
            best = candidate;
        }
    }

    Ok(best)
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn ocr_decoded_page_images(
    config: &ResolvedOcrModelConfig,
    images: &[RgbImage],
    cache_slot: Option<usize>,
) -> Result<(Option<String>, usize)> {
    let mut attempts = 0usize;
    let mut best_page_result: Option<OcrTextResult> = None;

    for image in images {
        attempts = attempts.saturating_add(1);
        let text_result = run_ocr_with_cached_model(config, image, cache_slot)?;
        if text_result.text.is_empty() {
            continue;
        }
        if is_better_ocr_text_result(&text_result, best_page_result.as_ref()) {
            best_page_result = Some(text_result);
        }
    }

    let text = best_page_result.and_then(|result| (!result.text.is_empty()).then_some(result.text));
    Ok((text, attempts))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn should_accept_primary_orientation(result: &OcrTextResult) -> bool {
    if result.text.is_empty() {
        return false;
    }
    result.char_count >= OCR_PRIMARY_ORIENTATION_MIN_CHARS
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn keep_ocr_line(text: &str, score: f32) -> Option<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    if !score.is_finite() || score < OCR_TEXT_SCORE_THRESH {
        return None;
    }
    Some(trimmed.to_string())
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn build_ocr_text_result(result: paddle_ocr_rs::ocr_result::OcrResult) -> OcrTextResult {
    let mut lines = Vec::<String>::new();
    let mut weighted_score_sum = 0f32;
    let mut weighted_char_sum = 0usize;

    for block in result.text_blocks {
        let Some(line) = keep_ocr_line(&block.text, block.text_score) else {
            continue;
        };
        let line_char_count = line.chars().count().max(1);
        lines.push(line);
        weighted_score_sum += block.text_score * line_char_count as f32;
        weighted_char_sum = weighted_char_sum.saturating_add(line_char_count);
    }

    let text = normalize_text_keep_paragraphs(&lines.join("\n"));
    let char_count = text.chars().count();
    if char_count == 0 || weighted_char_sum == 0 {
        return OcrTextResult::default();
    }
    let avg_line_score = weighted_score_sum / weighted_char_sum as f32;
    let quality_score = compute_ocr_quality_score(avg_line_score, char_count);
    OcrTextResult {
        text,
        avg_line_score,
        char_count,
        quality_score,
    }
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn compute_ocr_quality_score(avg_line_score: f32, char_count: usize) -> f32 {
    if !avg_line_score.is_finite() || char_count == 0 {
        return 0.0;
    }
    let confidence = avg_line_score.clamp(0.0, 1.0);
    confidence * (char_count as f32).sqrt()
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn is_better_ocr_text_result(candidate: &OcrTextResult, best: Option<&OcrTextResult>) -> bool {
    if candidate.text.is_empty() {
        return false;
    }
    let Some(best) = best else {
        return true;
    };
    if best.text.is_empty() {
        return true;
    }
    if candidate.quality_score > best.quality_score {
        return true;
    }
    if candidate.quality_score < best.quality_score {
        return false;
    }
    if candidate.avg_line_score > best.avg_line_score {
        return true;
    }
    if candidate.avg_line_score < best.avg_line_score {
        return false;
    }
    candidate.char_count > best.char_count
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn init_ocr_model(ocr: &mut OcrLite, config: &ResolvedOcrModelConfig) -> Result<()> {
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(2)
        .clamp(1, 4);

    let det = config.det_path.to_string_lossy().to_string();
    let cls = config.cls_path.to_string_lossy().to_string();
    let rec = config.rec_path.to_string_lossy().to_string();

    if let Some(dict_path) = &config.dict_path {
        let dict = dict_path.to_string_lossy().to_string();
        ocr.init_models_with_dict(&det, &cls, &rec, &dict, threads)
            .map_err(|e| anyhow!("paddle init with dict failed: {e}"))?;
    } else {
        ocr.init_models(&det, &cls, &rec, threads)
            .map_err(|e| anyhow!("paddle init failed: {e}"))?;
    }

    Ok(())
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn ensure_ocr_onnxruntime_loaded(config: &ResolvedOcrModelConfig) -> Result<()> {
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum InitState {
        Uninitialized,
        Initializing,
        Initialized,
    }

    static STATE: OnceLock<(Mutex<InitState>, Condvar)> = OnceLock::new();
    let (state, cv) = STATE.get_or_init(|| (Mutex::new(InitState::Uninitialized), Condvar::new()));

    {
        let mut guard = match state.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        loop {
            match *guard {
                InitState::Initialized => return Ok(()),
                InitState::Initializing => {
                    guard = match cv.wait(guard) {
                        Ok(g) => g,
                        Err(poisoned) => poisoned.into_inner(),
                    };
                }
                InitState::Uninitialized => {
                    *guard = InitState::Initializing;
                    break;
                }
            }
        }
    }

    let init_attempt = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| -> Result<()> {
        let dylib_path = find_onnxruntime_library_path(config).ok_or_else(|| {
            anyhow!(
                "onnxruntime library not found near OCR runtime (det={})",
                config.det_path.display()
            )
        })?;
        ort::init_from(dylib_path.to_string_lossy().to_string())
            .commit()
            .map_err(|e| anyhow!("ort init failed: {e}"))?;
        Ok(())
    }));

    let result: Result<()> = match init_attempt {
        Ok(r) => r,
        Err(p) => Err(anyhow!(
            "onnxruntime init panicked: {}",
            panic_payload_to_string(&*p)
        )),
    };

    let mut guard = match state.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    match result {
        Ok(()) => {
            *guard = InitState::Initialized;
            cv.notify_all();
            Ok(())
        }
        Err(e) => {
            *guard = InitState::Uninitialized;
            cv.notify_all();
            Err(e)
        }
    }
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn find_onnxruntime_library_path(config: &ResolvedOcrModelConfig) -> Option<PathBuf> {
    let mut candidates = Vec::<PathBuf>::new();
    let mut seen = HashSet::<PathBuf>::new();

    let mut push = |path: PathBuf| {
        if !path.is_dir() {
            return;
        }
        if seen.insert(path.clone()) {
            candidates.push(path);
        }
    };

    if let Some(model_root) = config.det_path.parent() {
        let model_root = model_root.to_path_buf();
        push(model_root.clone());
        push(model_root.join("onnxruntime"));

        if model_root
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n == "models")
        {
            if let Some(runtime_root) = model_root.parent() {
                let runtime_root = runtime_root.to_path_buf();
                push(runtime_root.clone());
                push(runtime_root.join("onnxruntime"));
            }
        }
    }

    for dir in candidates {
        if let Some(path) = find_onnxruntime_library_in_dir(&dir) {
            return Some(path);
        }
    }

    None
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn find_onnxruntime_library_in_dir(dir: &Path) -> Option<PathBuf> {
    let main_aliases: &[&str] = if cfg!(target_os = "windows") {
        &["onnxruntime.dll"]
    } else if cfg!(target_os = "macos") {
        &["libonnxruntime.dylib"]
    } else {
        &["libonnxruntime.so"]
    };

    if let Some(path) = find_existing_file(dir, main_aliases) {
        return Some(path);
    }

    let mut versioned = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok().map(|v| v.path()))
        .filter(|p| p.is_file())
        .filter(|p| {
            p.file_name().and_then(|n| n.to_str()).is_some_and(|n| {
                if cfg!(target_os = "windows") {
                    let lower = n.to_ascii_lowercase();
                    lower.starts_with("onnxruntime") && lower.ends_with(".dll")
                } else if cfg!(target_os = "macos") {
                    n.starts_with("libonnxruntime")
                        && n.contains(".dylib")
                        && !n.contains("providers_shared")
                } else {
                    n.starts_with("libonnxruntime")
                        && n.contains(".so")
                        && !n.contains("providers_shared")
                }
            })
        })
        .collect::<Vec<_>>();
    versioned.sort();
    versioned.into_iter().next()
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn panic_payload_to_string(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&'static str>() {
        return s.to_string();
    }
    if let Some(s) = payload.downcast_ref::<String>() {
        return s.clone();
    }
    "unknown panic payload".to_string()
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
type OcrModelHandle = Arc<Mutex<OcrLite>>;

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn ocr_cache() -> &'static Mutex<HashMap<String, OcrModelHandle>> {
    static CACHE: OnceLock<Mutex<HashMap<String, OcrModelHandle>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn find_existing_file(root: &Path, aliases: &[&str]) -> Option<PathBuf> {
    for alias in aliases {
        let candidate = root.join(alias);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

#[cfg(test)]
#[path = "ocr_tests.rs"]
mod tests;

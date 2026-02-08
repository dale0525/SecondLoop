use anyhow::{anyhow, Result};
use lopdf::Document;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use super::pdf_page_image_decode::{
    collect_page_image_candidates, decode_pdf_image_to_rgb, PdfImageCandidate,
};
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use image::RgbImage;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use paddle_ocr_rs::ocr_lite::OcrLite;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use std::collections::HashMap;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use std::sync::{Mutex, OnceLock};

const MAX_FULL_TEXT_BYTES: usize = 256 * 1024;
const MAX_EXCERPT_TEXT_BYTES: usize = 8 * 1024;
const OCR_MODEL_DIR_ENV: &str = "SECONDLOOP_OCR_MODEL_DIR";

const DET_MODEL_ALIASES: [&str; 3] = [
    "ch_PP-OCRv4_det_infer.onnx",
    "ch_PP-OCRv5_mobile_det.onnx",
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
    ocr_attempt_count: u32,
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
    _dpi: u32,
    language_hints: &str,
) -> Result<OcrPayload> {
    if bytes.is_empty() {
        return Err(anyhow!("missing pdf bytes"));
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
        "desktop_rust_pdf_image_decode_empty"
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
    _dpi: u32,
    _language_hints: &str,
) -> Result<OcrPayload> {
    if bytes.is_empty() {
        return Err(anyhow!("missing pdf bytes"));
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

struct DesktopPdfTextExtractResult {
    text: String,
    page_count: u32,
    processed_pages: u32,
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
    run_ocr_with_cached_model(&config, image)
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
            ocr_attempt_count: 0,
        });
    }

    let mut page_numbers: Vec<u32> = pages.keys().cloned().collect();
    page_numbers.sort_unstable();
    let take_count = usize::try_from(max_pages)
        .unwrap_or(usize::MAX)
        .min(page_numbers.len());

    let mut page_texts = Vec::new();
    let mut image_candidate_count = 0usize;
    let mut decoded_image_count = 0usize;
    let mut ocr_attempt_count = 0usize;
    for page_number in page_numbers.into_iter().take(take_count) {
        let Some(page_id) = pages.get(&page_number).copied() else {
            continue;
        };

        let mut image_candidates = collect_page_image_candidates(&doc, page_id);
        if image_candidates.is_empty() {
            continue;
        }
        image_candidate_count = image_candidate_count.saturating_add(image_candidates.len());

        image_candidates.sort_by(|a, b| {
            let area_a = i128::from(a.width).saturating_mul(i128::from(a.height));
            let area_b = i128::from(b.width).saturating_mul(i128::from(b.height));
            area_b.cmp(&area_a)
        });

        for candidate in image_candidates {
            let decoded = decode_pdf_image_to_rgb(
                &doc,
                PdfImageCandidate {
                    object_id: candidate.object_id,
                    width: candidate.width,
                    height: candidate.height,
                },
            );
            if let Some(rgb) = decoded {
                decoded_image_count = decoded_image_count.saturating_add(1);
                ocr_attempt_count = ocr_attempt_count.saturating_add(1);
                let text = run_ocr_with_cached_model(&config, &rgb)?;
                if !text.is_empty() {
                    page_texts.push(text);
                    break;
                }
            }
        }
    }

    Ok(PdfImageOcrFallbackResult {
        text: normalize_text_keep_paragraphs(&page_texts.join("\n")),
        model_available: true,
        image_candidate_count: u32::try_from(image_candidate_count).unwrap_or(u32::MAX),
        decoded_image_count: u32::try_from(decoded_image_count).unwrap_or(u32::MAX),
        ocr_attempt_count: u32::try_from(ocr_attempt_count).unwrap_or(u32::MAX),
    })
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn run_ocr_with_cached_model(config: &ResolvedOcrModelConfig, image: &RgbImage) -> Result<String> {
    ensure_ocr_onnxruntime_loaded(config)?;

    let cache = ocr_cache();
    let mut guard = match cache.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };

    if !guard.contains_key(&config.cache_key) {
        let mut ocr = OcrLite::new();
        init_ocr_model(&mut ocr, config)?;
        guard.insert(config.cache_key.clone(), ocr);
    }

    let ocr = guard
        .get_mut(&config.cache_key)
        .ok_or_else(|| anyhow!("ocr model cache unavailable"))?;

    let max_side_len = image.width().max(image.height()).clamp(1024, 3072);
    let result = ocr
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

    let lines = result
        .text_blocks
        .into_iter()
        .map(|block| block.text.trim().to_string())
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>();
    Ok(normalize_text_keep_paragraphs(&lines.join("\n")))
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

    static STATE: OnceLock<Mutex<InitState>> = OnceLock::new();
    let state = STATE.get_or_init(|| Mutex::new(InitState::Uninitialized));

    {
        let guard = match state.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        match *guard {
            InitState::Initialized => return Ok(()),
            InitState::Initializing => {
                return Err(anyhow!("onnxruntime init already in progress"));
            }
            InitState::Uninitialized => {}
        }
    }

    {
        let mut guard = match state.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        match *guard {
            InitState::Initialized => return Ok(()),
            InitState::Initializing => {
                return Err(anyhow!("onnxruntime init already in progress"));
            }
            InitState::Uninitialized => {
                *guard = InitState::Initializing;
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
            Ok(())
        }
        Err(e) => {
            *guard = InitState::Uninitialized;
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
fn ocr_cache() -> &'static Mutex<HashMap<String, OcrLite>> {
    static CACHE: OnceLock<Mutex<HashMap<String, OcrLite>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn resolve_ocr_model_config(
    language_hints: &str,
    model_dir: Option<&str>,
) -> Option<ResolvedOcrModelConfig> {
    let rec_preferences = preferred_rec_keys(language_hints);
    let roots = model_root_candidates(model_dir);

    for root in roots {
        let det_path = match find_existing_file(&root, &DET_MODEL_ALIASES) {
            Some(v) => v,
            None => continue,
        };
        let cls_path = match find_existing_file(&root, &CLS_MODEL_ALIASES) {
            Some(v) => v,
            None => continue,
        };

        if let Some(cfg) = build_rec_model_config(&root, &det_path, &cls_path, &rec_preferences) {
            return Some(cfg);
        }

        let all_keys = REC_MODEL_SPECS.iter().map(|s| s.key).collect::<Vec<_>>();
        if let Some(cfg) = build_rec_model_config(&root, &det_path, &cls_path, &all_keys) {
            return Some(cfg);
        }
    }

    None
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn build_rec_model_config(
    root: &Path,
    det_path: &Path,
    cls_path: &Path,
    rec_keys: &[&str],
) -> Option<ResolvedOcrModelConfig> {
    for key in rec_keys {
        let Some(spec) = REC_MODEL_SPECS.iter().find(|s| s.key == *key) else {
            continue;
        };

        let rec_path = match find_existing_file(root, spec.model_files) {
            Some(path) => path,
            None => continue,
        };

        let dict_path = if spec.dict_files.is_empty() {
            None
        } else {
            let candidate = match find_existing_file(root, spec.dict_files) {
                Some(path) => path,
                None => continue,
            };
            Some(candidate)
        };

        let cache_key = format!(
            "{}|{}|{}|{}",
            det_path.display(),
            cls_path.display(),
            rec_path.display(),
            dict_path
                .as_ref()
                .map(|p| p.display().to_string())
                .unwrap_or_default()
        );

        return Some(ResolvedOcrModelConfig {
            det_path: det_path.to_path_buf(),
            cls_path: cls_path.to_path_buf(),
            rec_path,
            dict_path,
            cache_key,
        });
    }

    None
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn preferred_rec_keys(language_hints: &str) -> Vec<&'static str> {
    let hint = language_hints.trim().to_ascii_lowercase();

    if hint.is_empty() || hint == "device_plus_en" {
        return vec![
            "zh_hans",
            "latin",
            "ja",
            "ko",
            "arabic",
            "cyrillic",
            "devanagari",
            "zh_hant",
        ];
    }

    if hint.contains("ja") {
        return vec!["ja", "zh_hans", "latin"];
    }
    if hint.contains("ko") {
        return vec!["ko", "zh_hans", "latin"];
    }
    if hint.contains("zh_strict") || hint.contains("zh_en") || hint == "zh" {
        return vec!["zh_hans", "zh_hant", "latin"];
    }
    if hint.contains("ar") {
        return vec!["arabic", "latin", "zh_hans"];
    }
    if hint.contains("ru") || hint.contains("cyrillic") {
        return vec!["cyrillic", "latin", "zh_hans"];
    }
    if hint.contains("hi") || hint.contains("devanagari") {
        return vec!["devanagari", "latin", "zh_hans"];
    }

    vec!["latin", "zh_hans", "ja"]
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn model_root_candidates(model_dir: Option<&str>) -> Vec<PathBuf> {
    let mut seen = HashSet::<PathBuf>::new();
    let mut roots = Vec::new();

    let mut push_dir = |path: &Path| {
        if path.as_os_str().is_empty() {
            return;
        }
        let base = path.to_path_buf();
        if base.is_dir() && seen.insert(base.clone()) {
            roots.push(base.clone());
        }

        let nested_models = base.join("models");
        if nested_models.is_dir() && seen.insert(nested_models.clone()) {
            roots.push(nested_models);
        }
    };

    if let Some(explicit) = model_dir {
        push_dir(Path::new(explicit.trim()));
    }

    if let Ok(from_env) = std::env::var(OCR_MODEL_DIR_ENV) {
        push_dir(Path::new(from_env.trim()));
    }

    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            push_dir(exe_dir);
            push_dir(&exe_dir.join("assets/ocr/desktop_runtime"));
            push_dir(&exe_dir.join("data/flutter_assets/assets/ocr/desktop_runtime"));
            push_dir(&exe_dir.join("../Resources/flutter_assets/assets/ocr/desktop_runtime"));
        }
    }

    if let Ok(cwd) = std::env::current_dir() {
        push_dir(&cwd);
        push_dir(&cwd.join("assets/ocr/desktop_runtime"));
    }

    roots
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

fn extract_pdf_text_with_limit(
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

    let text = match doc.extract_text(&selected_pages) {
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

    Ok(DesktopPdfTextExtractResult {
        text,
        page_count,
        processed_pages: u32::try_from(selected_pages.len()).unwrap_or(u32::MAX),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncate_utf8_keeps_valid_boundaries() {
        let text = "你好hello";
        let truncated = truncate_utf8(text, 5);
        assert_eq!(truncated, "你");
    }

    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    #[test]
    fn image_payload_uses_expected_shape_without_models() {
        let img = image::RgbImage::from_raw(1, 1, vec![255, 255, 255]).unwrap();
        let dynamic = image::DynamicImage::ImageRgb8(img);
        let mut bytes = Vec::new();
        dynamic
            .write_to(
                &mut std::io::Cursor::new(&mut bytes),
                image::ImageFormat::Png,
            )
            .unwrap();

        let payload = desktop_ocr_image(&bytes, "device_plus_en").unwrap();
        assert!(payload.ocr_engine.starts_with("desktop_rust_image_"));
        assert_eq!(payload.ocr_page_count, 1);
        assert_eq!(payload.ocr_processed_pages, 1);
    }

    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    #[test]
    fn resolve_ocr_model_config_accepts_v3_model_set() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        std::fs::write(root.join("ch_PP-OCRv3_det_infer.onnx"), b"det").unwrap();
        std::fs::write(root.join("ch_ppocr_mobile_v2.0_cls_infer.onnx"), b"cls").unwrap();
        std::fs::write(root.join("ch_PP-OCRv3_rec_infer.onnx"), b"rec").unwrap();

        let model_dir = root.to_string_lossy().to_string();
        let resolved = resolve_ocr_model_config("device_plus_en", Some(&model_dir));
        assert!(resolved.is_some());
    }

    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    #[test]
    fn resolve_ocr_model_config_accepts_v5_model_set() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        std::fs::write(root.join("ch_PP-OCRv5_mobile_det.onnx"), b"det").unwrap();
        std::fs::write(root.join("ch_ppocr_mobile_v2.0_cls_infer.onnx"), b"cls").unwrap();
        std::fs::write(root.join("ch_PP-OCRv5_rec_mobile_infer.onnx"), b"rec").unwrap();

        let model_dir = root.to_string_lossy().to_string();
        let resolved = resolve_ocr_model_config("device_plus_en", Some(&model_dir));
        assert!(resolved.is_some());
    }

    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    #[test]
    fn find_onnxruntime_library_from_runtime_payload_layout() {
        let temp = tempfile::tempdir().unwrap();
        let runtime_root = temp.path();
        let models_dir = runtime_root.join("models");
        let onnx_dir = runtime_root.join("onnxruntime");
        std::fs::create_dir_all(&models_dir).unwrap();
        std::fs::create_dir_all(&onnx_dir).unwrap();

        let det_path = models_dir.join("ch_PP-OCRv3_det_infer.onnx");
        let cls_path = models_dir.join("ch_ppocr_mobile_v2.0_cls_infer.onnx");
        let rec_path = models_dir.join("ch_PP-OCRv3_rec_infer.onnx");

        std::fs::write(&det_path, b"det").unwrap();
        std::fs::write(&cls_path, b"cls").unwrap();
        std::fs::write(&rec_path, b"rec").unwrap();

        let lib_name = if cfg!(target_os = "windows") {
            "onnxruntime.dll"
        } else if cfg!(target_os = "macos") {
            "libonnxruntime.dylib"
        } else {
            "libonnxruntime.so"
        };
        let lib_path = onnx_dir.join(lib_name);
        std::fs::write(&lib_path, b"ort").unwrap();

        let cfg = ResolvedOcrModelConfig {
            det_path,
            cls_path,
            rec_path,
            dict_path: None,
            cache_key: "test-cache-key".to_string(),
        };

        let resolved = find_onnxruntime_library_path(&cfg);
        assert_eq!(resolved, Some(lib_path));
    }
}

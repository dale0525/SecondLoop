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
fn resolve_ocr_model_config_prefers_v5_detector_when_v4_also_exists() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    std::fs::write(root.join("ch_PP-OCRv4_det_infer.onnx"), b"det-v4").unwrap();
    std::fs::write(root.join("ch_PP-OCRv5_mobile_det.onnx"), b"det-v5").unwrap();
    std::fs::write(root.join("ch_ppocr_mobile_v2.0_cls_infer.onnx"), b"cls").unwrap();
    std::fs::write(root.join("ch_PP-OCRv5_rec_mobile_infer.onnx"), b"rec").unwrap();

    let model_dir = root.to_string_lossy().to_string();
    let resolved = resolve_ocr_model_config("device_plus_en", Some(&model_dir))
        .expect("expected v5 config to resolve");
    let det_name = resolved
        .det_path
        .file_name()
        .and_then(|v| v.to_str())
        .unwrap_or_default();
    assert_eq!(det_name, "ch_PP-OCRv5_mobile_det.onnx");
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

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn keep_ocr_line_filters_low_confidence_noise() {
    assert_eq!(keep_ocr_line("", 0.99), None);
    assert_eq!(keep_ocr_line("   ", 0.99), None);
    assert_eq!(keep_ocr_line("乱码", 0.12), None);
    assert_eq!(keep_ocr_line("abc", f32::NAN), None);
    assert_eq!(
        keep_ocr_line("  clean text  ", 0.75),
        Some("clean text".to_string())
    );
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn ocr_quality_score_prefers_higher_confidence_and_longer_text() {
    let low = compute_ocr_quality_score(0.55, 10);
    let high_conf = compute_ocr_quality_score(0.9, 10);
    let high_len = compute_ocr_quality_score(0.55, 100);
    assert!(high_conf > low);
    assert!(high_len > low);
    assert_eq!(compute_ocr_quality_score(f32::NAN, 30), 0.0);
    assert_eq!(compute_ocr_quality_score(0.8, 0), 0.0);
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn is_better_ocr_text_result_uses_quality_then_confidence_then_length() {
    let best = OcrTextResult {
        text: "a".to_string(),
        avg_line_score: 0.8,
        char_count: 10,
        quality_score: 2.5,
    };
    let better_quality = OcrTextResult {
        text: "b".to_string(),
        avg_line_score: 0.7,
        char_count: 20,
        quality_score: 3.0,
    };
    let better_confidence = OcrTextResult {
        text: "c".to_string(),
        avg_line_score: 0.85,
        char_count: 10,
        quality_score: 2.5,
    };
    let better_length = OcrTextResult {
        text: "d".to_string(),
        avg_line_score: 0.8,
        char_count: 12,
        quality_score: 2.5,
    };

    assert!(is_better_ocr_text_result(&better_quality, Some(&best)));
    assert!(is_better_ocr_text_result(&better_confidence, Some(&best)));
    assert!(is_better_ocr_text_result(&better_length, Some(&best)));
    assert!(!is_better_ocr_text_result(
        &OcrTextResult::default(),
        Some(&best)
    ));
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn should_accept_primary_orientation_requires_minimum_non_empty_text() {
    let empty = OcrTextResult::default();
    assert!(!should_accept_primary_orientation(&empty));

    let short = OcrTextResult {
        text: "short text".to_string(),
        avg_line_score: 0.9,
        char_count: 10,
        quality_score: 2.8,
    };
    assert!(!should_accept_primary_orientation(&short));

    let enough = OcrTextResult {
        text: "this is enough text to skip extra orientation checks".to_string(),
        avg_line_score: 0.8,
        char_count: OCR_PRIMARY_ORIENTATION_MIN_CHARS,
        quality_score: 6.0,
    };
    assert!(should_accept_primary_orientation(&enough));
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn choose_ocr_page_worker_count_scales_by_pages_and_cpu() {
    assert_eq!(choose_ocr_page_worker_count(0, 8), 1);
    assert_eq!(choose_ocr_page_worker_count(1, 8), 1);
    assert_eq!(choose_ocr_page_worker_count(2, 8), 2);
    assert_eq!(choose_ocr_page_worker_count(11, 8), 2);
    assert_eq!(choose_ocr_page_worker_count(12, 8), 3);
    assert_eq!(choose_ocr_page_worker_count(22, 2), 2);
    assert_eq!(choose_ocr_page_worker_count(32, 8), 4);
    assert_eq!(choose_ocr_page_worker_count(48, 3), 3);
}

fn build_pdf_with_single_byte_tounicode_mapping() -> Vec<u8> {
    let content = "BT /F1 18 Tf 72 120 Td <212223> Tj ET\n";
    let cmap = "/CIDInit /ProcSet findresource begin\n\
12 dict begin\n\
begincmap\n\
/CIDSystemInfo <<\n\
  /Registry (Adobe)\n\
  /Ordering (UCS)\n\
  /Supplement 0\n\
>> def\n\
/CMapName /Adobe-Identity-UCS def\n\
/CMapType 2 def\n\
1 begincodespacerange\n\
<00><FF>\n\
endcodespacerange\n\
3 beginbfrange\n\
<21><21><4F60>\n\
<22><22><597D>\n\
<23><23><FF01>\n\
endbfrange\n\
endcmap\n\
CMapName currentdict /CMap defineresource pop\n\
end\n\
end\n";

    let mut parts: Vec<Vec<u8>> = Vec::new();
    parts.push(b"%PDF-1.4\n".to_vec());

    let obj1 = b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".to_vec();
    let obj2 = b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n".to_vec();
    let obj3 = b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n".to_vec();
    let obj4 = b"4 0 obj\n<< /Type /Font /Subtype /Type0 /BaseFont /DummyFont /Encoding /Identity-H /DescendantFonts [7 0 R] /ToUnicode 6 0 R >>\nendobj\n".to_vec();
    let obj5 = format!(
        "5 0 obj\n<< /Length {} >>\nstream\n{}endstream\nendobj\n",
        content.len(),
        content
    )
    .into_bytes();
    let obj6 = format!(
        "6 0 obj\n<< /Length {} >>\nstream\n{}endstream\nendobj\n",
        cmap.len(),
        cmap
    )
    .into_bytes();
    let obj7 = b"7 0 obj\n<< /Type /Font /Subtype /CIDFontType2 /BaseFont /DummyFont /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> >>\nendobj\n".to_vec();

    parts.push(obj1);
    parts.push(obj2);
    parts.push(obj3);
    parts.push(obj4);
    parts.push(obj5);
    parts.push(obj6);
    parts.push(obj7);

    let mut offsets: Vec<usize> = Vec::new();
    let mut cur = 0usize;
    for part in &parts {
        offsets.push(cur);
        cur += part.len();
    }

    let xref_start = cur;
    let mut xref = String::new();
    xref.push_str("xref\n0 8\n");
    xref.push_str("0000000000 65535 f \n");
    for offset in offsets.iter().take(8).skip(1) {
        xref.push_str(&format!("{:010} 00000 n \n", offset));
    }
    let trailer = format!(
        "trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{}\n%%EOF\n",
        xref_start
    );

    let mut out = Vec::<u8>::new();
    for part in parts {
        out.extend_from_slice(&part);
    }
    out.extend_from_slice(xref.as_bytes());
    out.extend_from_slice(trailer.as_bytes());
    out
}

#[test]
fn extract_pdf_text_with_limit_handles_single_byte_tounicode_cmap() {
    let pdf = build_pdf_with_single_byte_tounicode_mapping();
    let extracted = extract_pdf_text_with_limit(&pdf, 1).expect("extract text");
    let normalized = normalize_text_keep_paragraphs(&extracted.text);

    assert!(
        normalized.contains("你好"),
        "expected to decode one-byte ToUnicode mapping, got: {normalized:?}"
    );
}

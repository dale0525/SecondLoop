const kLinuxOnnxOcrBridgeScript = r'''
#!/usr/bin/env python3
import argparse
import json
import locale
import os
import sys
import tempfile

MAX_FULL_BYTES = 256 * 1024
MAX_EXCERPT_BYTES = 8 * 1024
MODEL_ENV_NAME = "SECONDLOOP_OCR_MODEL_DIR"
DEFAULT_LANGUAGE_HINT = "device_plus_en"
DEFAULT_REC_MODEL_KEY = "latin"
MODEL_FILE_NAME_ALIASES = {
    "det_model_path": "ch_PP-OCRv4_det_infer.onnx",
    "cls_model_path": "ch_ppocr_mobile_v2.0_cls_infer.onnx",
    "rec_models": {
        "latin": {
            "model": "latin_PP-OCRv3_rec_infer.onnx",
            "dict": "latin_dict.txt",
        },
        "arabic": {
            "model": "arabic_PP-OCRv3_rec_infer.onnx",
            "dict": "arabic_dict.txt",
        },
        "cyrillic": {
            "model": "cyrillic_PP-OCRv3_rec_infer.onnx",
            "dict": "cyrillic_dict.txt",
        },
        "devanagari": {
            "model": "devanagari_PP-OCRv3_rec_infer.onnx",
            "dict": "devanagari_dict.txt",
        },
        "ja": {
            "model": "japan_PP-OCRv3_rec_infer.onnx",
            "dict": "japan_dict.txt",
        },
        "ko": {
            "model": "korean_PP-OCRv3_rec_infer.onnx",
            "dict": "korean_dict.txt",
        },
        "zh_hant": {
            "model": "chinese_cht_PP-OCRv3_rec_infer.onnx",
            "dict": "chinese_cht_dict.txt",
        },
        "zh_hans": {
            "model": "ch_PP-OCRv4_rec_infer.onnx",
            "dict": None,
        },
    },
}


def truncate_utf8(text, max_bytes):
    data = text.encode("utf-8")
    if len(data) <= max_bytes:
        return text
    if max_bytes <= 0:
        return ""
    end = max_bytes
    while end > 0 and (data[end] & 0xC0) == 0x80:
        end -= 1
    if end <= 0:
        return ""
    return data[:end].decode("utf-8", errors="ignore")


def ensure_module(import_name):
    try:
        __import__(import_name)
        return True
    except Exception:
        return False


def parse_rapidocr_result(raw):
    if not raw:
        return ""
    lines = []
    for item in raw:
        if not isinstance(item, (list, tuple)):
            continue
        if len(item) < 2:
            continue
        text = str(item[1]).strip()
        if text:
            lines.append(text)
    return "\n".join(lines).strip()


def build_payload(full_text, page_count, processed_pages, engine="onnx_ocr"):
    full = full_text.strip()
    full_truncated = truncate_utf8(full, MAX_FULL_BYTES)
    excerpt = truncate_utf8(full_truncated, MAX_EXCERPT_BYTES)
    is_truncated = full_truncated != full or processed_pages < page_count
    return {
        "ocr_text_full": full_truncated,
        "ocr_text_excerpt": excerpt,
        "ocr_engine": engine,
        "ocr_is_truncated": bool(is_truncated),
        "ocr_page_count": int(page_count),
        "ocr_processed_pages": int(processed_pages),
    }


def normalize_hint(value):
    hint = str(value or "").strip().lower()
    if not hint:
        return DEFAULT_LANGUAGE_HINT
    return hint


def _locale_to_model_key(raw):
    value = str(raw or "").strip().lower()
    if not value:
        return DEFAULT_REC_MODEL_KEY
    value = value.split(".")[0]
    value = value.replace("-", "_")
    lang = value.split("_")[0]

    if lang == "zh":
        if any(tag in value for tag in ["hant", "tw", "hk", "mo"]):
            return "zh_hant"
        return "zh_hans"
    if lang == "ja":
        return "ja"
    if lang == "ko":
        return "ko"
    if lang in ["ar", "fa", "ur"]:
        return "arabic"
    if lang in ["ru", "uk", "bg", "be", "kk", "ky", "mk", "mn", "sr"]:
        return "cyrillic"
    if lang in ["hi", "mr", "ne"]:
        return "devanagari"
    return DEFAULT_REC_MODEL_KEY


def resolve_locale_model_key():
    locale_candidates = []
    try:
        locale_value = locale.getlocale()[0]
        if locale_value:
            locale_candidates.append(locale_value)
    except Exception:
        pass
    try:
        default_locale = locale.getdefaultlocale()[0]
        if default_locale:
            locale_candidates.append(default_locale)
    except Exception:
        pass
    for env_key in ["LC_ALL", "LC_CTYPE", "LANG"]:
        env_value = os.environ.get(env_key)
        if env_value:
            locale_candidates.append(env_value)
    for candidate in locale_candidates:
        key = _locale_to_model_key(candidate)
        if key:
            return key
    return DEFAULT_REC_MODEL_KEY


def _dedupe_non_empty(values):
    seen = set()
    ordered = []
    for value in values:
        key = str(value or "").strip()
        if not key:
            continue
        if key in seen:
            continue
        seen.add(key)
        ordered.append(key)
    return ordered


def select_rec_model_keys(language_hints, use_pdf_auto_detect=False):
    hint = normalize_hint(language_hints)
    hint_map = {
        "en": ["latin"],
        "fr_en": ["latin"],
        "de_en": ["latin"],
        "es_en": ["latin"],
        "zh_en": ["zh_hans"],
        "zh_strict": ["zh_hans"],
        "ja_en": ["ja"],
        "ko_en": ["ko"],
    }
    if hint == "device_plus_en":
        preferred = resolve_locale_model_key()
        if use_pdf_auto_detect:
            # Keep auto-probe compact: prioritize locale-aligned models first.
            if preferred == "zh_hant":
                ordered_keys = ["zh_hant", "zh_hans", "latin"]
            elif preferred in ["ja", "ko", "arabic", "cyrillic", "devanagari"]:
                ordered_keys = [preferred, "latin", "zh_hans"]
            elif preferred == "zh_hans":
                ordered_keys = ["zh_hans", "latin", "ja"]
            else:
                ordered_keys = ["zh_hans", "latin", "ja"]
        else:
            if preferred in [
                "arabic",
                "cyrillic",
                "devanagari",
                "ja",
                "ko",
                "zh_hant",
                "zh_hans",
            ]:
                ordered_keys = [preferred, "zh_hans", "latin"]
            else:
                ordered_keys = ["zh_hans", "latin"]
    else:
        preferred = hint_map.get(hint)
        if preferred is None:
            preferred = [resolve_locale_model_key()]
        ordered_keys = list(preferred) + [DEFAULT_REC_MODEL_KEY, "zh_hans"]
    return _dedupe_non_empty(ordered_keys)


def resolve_rapidocr_candidates(language_hints, use_pdf_auto_detect=False):
    model_dir = os.environ.get(MODEL_ENV_NAME, "").strip()
    if not model_dir:
        return []

    det_name = MODEL_FILE_NAME_ALIASES["det_model_path"]
    cls_name = MODEL_FILE_NAME_ALIASES["cls_model_path"]
    det_path = os.path.join(model_dir, det_name)
    cls_path = os.path.join(model_dir, cls_name)
    if not os.path.exists(det_path) or not os.path.exists(cls_path):
        return []

    rec_specs = MODEL_FILE_NAME_ALIASES["rec_models"]
    candidates = []
    for rec_model_key in select_rec_model_keys(
        language_hints,
        use_pdf_auto_detect=use_pdf_auto_detect,
    ):
        rec_spec = rec_specs.get(rec_model_key)
        if rec_spec is None:
            continue
        rec_name = rec_spec.get("model")
        rec_dict_name = rec_spec.get("dict")
        if not rec_name:
            continue
        rec_path = os.path.join(model_dir, rec_name)
        if not os.path.exists(rec_path):
            continue
        kwargs = {
            "det_model_path": det_path,
            "cls_model_path": cls_path,
            "rec_model_path": rec_path,
        }
        if rec_dict_name:
            rec_dict_path = os.path.join(model_dir, rec_dict_name)
            if not os.path.exists(rec_dict_path):
                continue
            kwargs["rec_keys_path"] = rec_dict_path
        candidates.append((rec_model_key, kwargs))
    return candidates


def resolve_rapidocr_kwargs(language_hints):
    candidates = resolve_rapidocr_candidates(
        language_hints,
        use_pdf_auto_detect=False,
    )
    if not candidates:
        return None, None
    return candidates[0]


def _script_counters(text):
    counters = {
        "non_space": 0,
        "digit": 0,
        "latin": 0,
        "han": 0,
        "kana": 0,
        "hangul": 0,
        "arabic": 0,
        "cyrillic": 0,
        "devanagari": 0,
    }
    for ch in text:
        if ch.isspace():
            continue
        counters["non_space"] += 1
        code = ord(ch)
        if 0x30 <= code <= 0x39:
            counters["digit"] += 1
        if (0x41 <= code <= 0x5A) or (0x61 <= code <= 0x7A):
            counters["latin"] += 1
        if (
            (0x3400 <= code <= 0x4DBF)
            or (0x4E00 <= code <= 0x9FFF)
            or (0xF900 <= code <= 0xFAFF)
        ):
            counters["han"] += 1
        if (
            (0x3040 <= code <= 0x309F)
            or (0x30A0 <= code <= 0x30FF)
            or (0x31F0 <= code <= 0x31FF)
        ):
            counters["kana"] += 1
        if (
            (0x1100 <= code <= 0x11FF)
            or (0x3130 <= code <= 0x318F)
            or (0xAC00 <= code <= 0xD7AF)
        ):
            counters["hangul"] += 1
        if 0x0600 <= code <= 0x06FF:
            counters["arabic"] += 1
        if (0x0400 <= code <= 0x04FF) or (0x0500 <= code <= 0x052F):
            counters["cyrillic"] += 1
        if 0x0900 <= code <= 0x097F:
            counters["devanagari"] += 1
    return counters


def score_text_for_model(text, rec_model_key):
    counters = _script_counters(text or "")
    non_space = counters["non_space"]
    if non_space <= 0:
        return 0

    score = non_space * 2 + counters["digit"] * 2
    if rec_model_key == "zh_hans" or rec_model_key == "zh_hant":
        score += counters["han"] * 12
        score += counters["latin"] * 2
        score += counters["digit"] * 2
        if counters["han"] == 0:
            score -= 300
    elif rec_model_key == "ja":
        score += counters["kana"] * 14
        score += counters["han"] * 4
        score += counters["latin"] * 2
        if counters["kana"] == 0 and counters["han"] == 0:
            score -= 300
    elif rec_model_key == "ko":
        score += counters["hangul"] * 14
        score += counters["han"] * 2
        score += counters["latin"] * 2
        if counters["hangul"] == 0:
            score -= 300
    elif rec_model_key == "arabic":
        score += counters["arabic"] * 14
        score += counters["digit"] * 3
        if counters["arabic"] == 0:
            score -= 300
    elif rec_model_key == "cyrillic":
        score += counters["cyrillic"] * 14
        score += counters["digit"] * 3
        if counters["cyrillic"] == 0:
            score -= 300
    elif rec_model_key == "devanagari":
        score += counters["devanagari"] * 14
        score += counters["digit"] * 3
        if counters["devanagari"] == 0:
            score -= 300
    else:
        score += counters["latin"] * 10
        score += counters["digit"] * 3
        score -= (
            counters["han"]
            + counters["kana"]
            + counters["hangul"]
            + counters["arabic"]
            + counters["cyrillic"]
            + counters["devanagari"]
        ) * 3
    return score


def ocr_pdf_page_text(doc, page_index, scale, engine):
    page = doc[page_index]
    bitmap = page.render(scale=scale)
    pil_image = bitmap.to_pil()
    temp_png = None
    try:
        with tempfile.NamedTemporaryFile(
            suffix=".png",
            delete=False,
        ) as temp_file:
            temp_png = temp_file.name
        pil_image.save(temp_png, format="PNG")
        result, _ = engine(temp_png)
        return parse_rapidocr_result(result)
    finally:
        try:
            page.close()
        except Exception:
            pass
        try:
            bitmap.close()
        except Exception:
            pass
        try:
            pil_image.close()
        except Exception:
            pass
        if temp_png:
            try:
                os.remove(temp_png)
            except Exception:
                pass


def auto_detect_pdf_rec_model_key(
    doc,
    candidate_kwargs,
    target_pages,
    dpi,
    rapid_ocr_cls,
):
    if not candidate_kwargs:
        return None
    probe_pages = min(target_pages, 1)
    if probe_pages <= 0:
        return candidate_kwargs[0][0]
    probe_scale = max(float(min(dpi, 220)), 120.0) / 72.0
    best_key = candidate_kwargs[0][0]
    best_score = -1_000_000_000
    for rec_model_key, kwargs in candidate_kwargs:
        try:
            engine = rapid_ocr_cls(**kwargs)
        except Exception:
            continue
        model_score = 0
        for index in range(probe_pages):
            probe_text = ocr_pdf_page_text(doc, index, probe_scale, engine)
            model_score += score_text_for_model(probe_text, rec_model_key)
        if model_score > best_score:
            best_score = model_score
            best_key = rec_model_key
    return best_key


def run_image_ocr(input_path, language_hints):
    if not ensure_module("rapidocr_onnxruntime"):
        raise RuntimeError("missing rapidocr_onnxruntime")
    from rapidocr_onnxruntime import RapidOCR

    kwargs, rec_model_key = resolve_rapidocr_kwargs(language_hints)
    if kwargs is None:
        raise RuntimeError("missing_onnx_models")
    engine = RapidOCR(**kwargs)
    result, _ = engine(input_path)
    text = parse_rapidocr_result(result)
    return build_payload(text, 1, 1, engine=f"onnx_ocr+{rec_model_key}")


def run_pdf_ocr(input_path, max_pages, dpi, language_hints):
    if not ensure_module("rapidocr_onnxruntime"):
        raise RuntimeError("missing rapidocr_onnxruntime")
    if not ensure_module("pypdfium2"):
        raise RuntimeError("missing pypdfium2")
    from rapidocr_onnxruntime import RapidOCR
    import pypdfium2 as pdfium

    doc = pdfium.PdfDocument(input_path)
    page_count = len(doc)
    if page_count <= 0:
        return build_payload("", 0, 0, engine="onnx_ocr+none")

    target_pages = min(page_count, max_pages)
    hint = normalize_hint(language_hints)
    use_auto_detect = hint == "device_plus_en"
    candidates = resolve_rapidocr_candidates(
        language_hints,
        use_pdf_auto_detect=use_auto_detect,
    )
    if not candidates:
        raise RuntimeError("missing_onnx_models")

    if use_auto_detect:
        detected_key = auto_detect_pdf_rec_model_key(
            doc,
            candidates,
            target_pages,
            dpi,
            RapidOCR,
        )
        selected_key = detected_key or candidates[0][0]
        selected_kwargs = None
        for rec_model_key, kwargs in candidates:
            if rec_model_key == selected_key:
                selected_kwargs = kwargs
                break
        if selected_kwargs is None:
            selected_key, selected_kwargs = candidates[0]
        engine_label = f"onnx_ocr+{selected_key}+auto"
    else:
        selected_key, selected_kwargs = candidates[0]
        engine_label = f"onnx_ocr+{selected_key}"

    engine = RapidOCR(**selected_kwargs)
    processed_pages = 0
    blocks = []
    scale = max(float(dpi), 72.0) / 72.0

    for index in range(target_pages):
        page_text = ocr_pdf_page_text(doc, index, scale, engine)
        processed_pages += 1
        if page_text:
            blocks.append(f"[page {index + 1}]\n{page_text}")

    full_text = "\n\n".join(blocks)
    return build_payload(
        full_text,
        page_count,
        processed_pages,
        engine=engine_label,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["image", "pdf"], required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--max-pages", type=int, default=200)
    parser.add_argument("--dpi", type=int, default=180)
    parser.add_argument("--language-hints", default="device_plus_en")
    args = parser.parse_args()

    try:
        if args.mode == "image":
            payload = run_image_ocr(args.input, args.language_hints)
        else:
            payload = run_pdf_ocr(
                input_path=args.input,
                max_pages=max(1, int(args.max_pages)),
                dpi=max(72, int(args.dpi)),
                language_hints=args.language_hints,
            )
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception:
        return 1


if __name__ == "__main__":
    sys.exit(main())
''';

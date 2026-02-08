use std::collections::HashSet;
use std::path::{Path, PathBuf};

use super::{
    find_existing_file, ResolvedOcrModelConfig, CLS_MODEL_ALIASES, DET_MODEL_ALIASES,
    OCR_MODEL_DIR_ENV, REC_MODEL_SPECS,
};

pub(super) fn resolve_ocr_model_config(
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

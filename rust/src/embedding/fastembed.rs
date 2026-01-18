use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{anyhow, Context, Result};
use flate2::read::GzDecoder;
use tar::Archive;
use zip::ZipArchive;

use super::{Embedder, DEFAULT_EMBED_DIM, PRODUCTION_MODEL_NAME};

const ONNXRUNTIME_VERSION: &str = "1.23.0";

#[derive(Clone)]
pub struct FastEmbedder {
    inner: Arc<FastEmbedderInner>,
}

struct FastEmbedderInner {
    model: Mutex<fastembed::TextEmbedding>,
}

impl FastEmbedder {
    pub fn get_or_try_init(app_dir: &Path) -> Result<Self> {
        static CACHE: OnceLock<Mutex<Option<FastEmbedder>>> = OnceLock::new();
        let cache = CACHE.get_or_init(|| Mutex::new(None));

        {
            let guard = match cache.lock() {
                Ok(g) => g,
                Err(poisoned) => poisoned.into_inner(),
            };
            if let Some(existing) = guard.as_ref() {
                return Ok(existing.clone());
            }
        }

        let embedder = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| Self::try_new(app_dir)))
            .map_err(|p| anyhow!("fastembed init panicked: {}", panic_payload_to_string(&p)))??;

        let mut guard = match cache.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard = Some(embedder.clone());
        Ok(embedder)
    }

    pub fn try_new(app_dir: &Path) -> Result<Self> {
        ensure_onnxruntime_loaded(app_dir)?;

        let cache_dir = app_dir.join("models").join("fastembed");
        fs::create_dir_all(&cache_dir)?;

        let options = fastembed::TextInitOptions::new(fastembed::EmbeddingModel::MultilingualE5Small)
            .with_cache_dir(cache_dir)
            .with_show_download_progress(false);

        let mut model =
            fastembed::TextEmbedding::try_new(options).context("fastembed: init model")?;

        let sanity = model
            .embed(vec!["query: hello"], Some(1))
            .context("fastembed: sanity embed")?;
        let dim = sanity
            .first()
            .map(|v| v.len())
            .unwrap_or_default();
        if dim != DEFAULT_EMBED_DIM {
            return Err(anyhow!(
                "fastembed dim mismatch: expected {}, got {}",
                DEFAULT_EMBED_DIM,
                dim
            ));
        }

        Ok(Self {
            inner: Arc::new(FastEmbedderInner {
                model: Mutex::new(model),
            }),
        })
    }
}

impl Embedder for FastEmbedder {
    fn model_name(&self) -> &str {
        PRODUCTION_MODEL_NAME
    }

    fn dim(&self) -> usize {
        DEFAULT_EMBED_DIM
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let mut model = match self.inner.model.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        let inputs: Vec<&str> = texts.iter().map(|t| t.as_str()).collect();
        let embeddings = model
            .embed(inputs, None)
            .context("fastembed: embed")?;

        if embeddings.iter().any(|v| v.len() != DEFAULT_EMBED_DIM) {
            return Err(anyhow!("fastembed returned unexpected embedding dimension"));
        }

    Ok(embeddings)
    }
}

fn ensure_onnxruntime_loaded(app_dir: &Path) -> Result<()> {
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
        #[cfg(test)]
        {
            if test_force_panic_onnxruntime_init() {
                panic!("forced panic in ensure_onnxruntime_loaded (test)");
            }
        }

        let dylib_path = ensure_onnxruntime_dylib(app_dir)?;
        let dylib_path = dylib_path.to_string_lossy().to_string();
        ort::init_from(dylib_path)
            .commit()
            .context("ort: commit")?;
        Ok(())
    }));

    let result: Result<()> = match init_attempt {
        Ok(r) => r,
        Err(p) => Err(anyhow!(
            "onnxruntime init panicked: {}",
            panic_payload_to_string(&p)
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

fn panic_payload_to_string(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&'static str>() {
        return s.to_string();
    }
    if let Some(s) = payload.downcast_ref::<String>() {
        return s.clone();
    }
    "unknown panic payload".to_string()
}

#[cfg(test)]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(test)]
static FORCE_PANIC_ONNXRUNTIME_INIT: AtomicBool = AtomicBool::new(false);
#[cfg(test)]
fn test_force_panic_onnxruntime_init() -> bool {
    FORCE_PANIC_ONNXRUNTIME_INIT.load(Ordering::SeqCst)
}
#[cfg(test)]
fn set_test_force_panic_onnxruntime_init(enabled: bool) {
    FORCE_PANIC_ONNXRUNTIME_INIT.store(enabled, Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ensure_onnxruntime_loaded_does_not_panic_or_poison_on_panic() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        set_test_force_panic_onnxruntime_init(true);

        let _ = ensure_onnxruntime_loaded(temp_dir.path())
            .expect_err("forced panic should be caught as error");
        let _ = ensure_onnxruntime_loaded(temp_dir.path())
            .expect_err("forced panic should be caught as error again");

        set_test_force_panic_onnxruntime_init(false);
    }
}

fn ensure_onnxruntime_dylib(app_dir: &Path) -> Result<PathBuf> {
    let runtime_dir = app_dir.join("onnxruntime");
    fs::create_dir_all(&runtime_dir)?;

    let main_name = onnxruntime_main_dylib_name()?;
    let main_path = runtime_dir.join(main_name);
    if main_path.exists() {
        return Ok(main_path);
    }

    let archive_name = onnxruntime_archive_name()?;
    let url = format!(
        "https://github.com/microsoft/onnxruntime/releases/download/v{ONNXRUNTIME_VERSION}/{archive_name}"
    );

    let tmp_path = runtime_dir.join(format!("{archive_name}.download"));
    download_to_file(&url, &tmp_path).context("download onnxruntime")?;

    if archive_name.ends_with(".zip") {
        extract_zip_runtime_libs(&tmp_path, &runtime_dir)?;
    } else {
        extract_tgz_runtime_libs(&tmp_path, &runtime_dir)?;
    }

    let _ = fs::remove_file(&tmp_path);

    if !main_path.exists() {
        ensure_main_dylib_fallbacks(&runtime_dir, &main_path)?;
    }

    if !main_path.exists() {
        return Err(anyhow!(
            "onnxruntime dylib missing after extraction: {}",
            main_path.display()
        ));
    }

    Ok(main_path)
}

fn download_to_file(url: &str, path: &Path) -> Result<()> {
    let mut resp = reqwest::blocking::get(url).with_context(|| format!("GET {url}"))?;
    if !resp.status().is_success() {
        return Err(anyhow!("download failed: {url} ({})", resp.status()));
    }

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let tmp = path.with_extension("partial");
    let mut out = File::create(&tmp)?;
    io::copy(&mut resp, &mut out)?;
    fs::rename(tmp, path)?;
    Ok(())
}

fn extract_zip_runtime_libs(zip_path: &Path, out_dir: &Path) -> Result<()> {
    let file = File::open(zip_path)?;
    let mut archive = ZipArchive::new(file).context("open zip")?;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let name = entry.name().to_string();
        if name.ends_with('/') {
            continue;
        }

        if !name.contains("/lib/") {
            continue;
        }

        let is_dll = name.to_lowercase().ends_with(".dll");
        if !is_dll {
            continue;
        }

        let Some(file_name) = Path::new(&name).file_name() else {
            continue;
        };
        let out_path = out_dir.join(file_name);

        let mut out = File::create(&out_path)?;
        io::copy(&mut entry, &mut out)?;
    }

    Ok(())
}

fn extract_tgz_runtime_libs(tgz_path: &Path, out_dir: &Path) -> Result<()> {
    let file = File::open(tgz_path)?;
    let decoder = GzDecoder::new(file);
    let mut archive = Archive::new(decoder);

    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?.to_path_buf();
        let path_str = path.to_string_lossy();
        if !path_str.contains("/lib/") {
            continue;
        }

        let Some(file_name) = path.file_name() else {
            continue;
        };
        let file_name_str = file_name.to_string_lossy();

        let looks_like_onnxruntime = file_name_str.starts_with("libonnxruntime");
        if !looks_like_onnxruntime {
            continue;
        }

        let is_lib = file_name_str.ends_with(".dylib")
            || file_name_str.contains(".dylib.")
            || file_name_str.ends_with(".so")
            || file_name_str.contains(".so.");
        if !is_lib {
            continue;
        }

        if !entry.header().entry_type().is_file() {
            continue;
        }

        let out_path = out_dir.join(file_name);
        let mut out = File::create(&out_path)?;
        io::copy(&mut entry, &mut out)?;
    }

    Ok(())
}

fn ensure_main_dylib_fallbacks(runtime_dir: &Path, main_path: &Path) -> Result<()> {
    let main_file_name = main_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default();

    let candidates: Vec<PathBuf> = fs::read_dir(runtime_dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_file())
        .filter(|p| {
            p.file_name().and_then(|n| n.to_str()).is_some_and(|n| {
                n.starts_with("libonnxruntime")
                    && !n.contains("providers_shared")
                    && n != main_file_name
            })
        })
        .collect();

    let Some(best) = candidates
        .iter()
        .find(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.contains(ONNXRUNTIME_VERSION)))
        .or_else(|| candidates.first())
        .cloned()
    else {
        return Ok(());
    };

    fs::copy(best, main_path)?;
    Ok(())
}

fn onnxruntime_archive_name() -> Result<String> {
    if cfg!(all(target_os = "windows", target_arch = "x86_64")) {
        return Ok(format!("onnxruntime-win-x64-{ONNXRUNTIME_VERSION}.zip"));
    }

    if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
        return Ok(format!("onnxruntime-osx-arm64-{ONNXRUNTIME_VERSION}.tgz"));
    }

    if cfg!(all(target_os = "macos", target_arch = "x86_64")) {
        return Ok(format!(
            "onnxruntime-osx-x86_64-{ONNXRUNTIME_VERSION}.tgz"
        ));
    }

    if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
        return Ok(format!("onnxruntime-linux-x64-{ONNXRUNTIME_VERSION}.tgz"));
    }

    if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
        return Ok(format!(
            "onnxruntime-linux-aarch64-{ONNXRUNTIME_VERSION}.tgz"
        ));
    }

    Err(anyhow!(
        "unsupported platform for onnxruntime download (os={}, arch={})",
        std::env::consts::OS,
        std::env::consts::ARCH
    ))
}

fn onnxruntime_main_dylib_name() -> Result<&'static str> {
    if cfg!(target_os = "windows") {
        return Ok("onnxruntime.dll");
    }
    if cfg!(target_os = "macos") {
        return Ok("libonnxruntime.dylib");
    }
    if cfg!(target_os = "linux") {
        return Ok("libonnxruntime.so");
    }

    Err(anyhow!("unsupported target_os for onnxruntime dylib"))
}

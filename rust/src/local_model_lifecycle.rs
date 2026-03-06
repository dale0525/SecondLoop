use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct LocalModelLifecycleStatus {
    pub strategy: String,
    pub loaded: bool,
    pub entry_count: u32,
    pub last_used_ms_ago: Option<u64>,
}

impl LocalModelLifecycleStatus {
    pub fn cached(loaded: bool, entry_count: u32, last_used_ms_ago: Option<u64>) -> Self {
        Self {
            strategy: "cached".to_string(),
            loaded,
            entry_count,
            last_used_ms_ago,
        }
    }

    pub fn ephemeral(last_used_ms_ago: Option<u64>) -> Self {
        Self {
            strategy: "ephemeral".to_string(),
            loaded: false,
            entry_count: 0,
            last_used_ms_ago,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct LocalModelLifecycleSnapshot {
    pub fastembed: LocalModelLifecycleStatus,
    pub ocr: LocalModelLifecycleStatus,
    pub whisper: LocalModelLifecycleStatus,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct LocalModelReleaseSummary {
    pub fastembed_released: bool,
    pub ocr_released_count: u32,
    pub whisper_released: bool,
    pub released_any: bool,
}

#[derive(Default)]
struct LocalWhisperUsageState {
    last_used_at: Option<Instant>,
}

fn local_whisper_usage_state() -> &'static Mutex<LocalWhisperUsageState> {
    static STATE: OnceLock<Mutex<LocalWhisperUsageState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(LocalWhisperUsageState::default()))
}

#[cfg_attr(not(test), allow(dead_code))]
fn elapsed_ms(instant: Instant) -> u64 {
    let millis = instant.elapsed().as_millis();
    millis.min(u128::from(u64::MAX)) as u64
}

#[cfg_attr(not(test), allow(dead_code))]
fn whisper_lifecycle_status() -> LocalModelLifecycleStatus {
    let guard = match local_whisper_usage_state().lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    let last_used_ms_ago = guard.last_used_at.map(elapsed_ms);
    LocalModelLifecycleStatus::ephemeral(last_used_ms_ago)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn snapshot() -> LocalModelLifecycleSnapshot {
    LocalModelLifecycleSnapshot {
        fastembed: crate::embedding::fastembed_lifecycle_status(),
        ocr: crate::desktop_media::ocr::ocr_lifecycle_status(),
        whisper: whisper_lifecycle_status(),
    }
}

pub(crate) fn mark_local_whisper_used() {
    let mut guard = match local_whisper_usage_state().lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    guard.last_used_at = Some(Instant::now());
}

pub(crate) fn release_all_if_idle(max_idle: Duration) -> LocalModelReleaseSummary {
    let fastembed_released = crate::embedding::release_fastembed_if_idle(max_idle);
    let ocr_released_count = crate::desktop_media::ocr::release_ocr_if_idle(max_idle);
    let whisper_released = false;

    LocalModelReleaseSummary {
        fastembed_released,
        ocr_released_count,
        whisper_released,
        released_any: fastembed_released || ocr_released_count > 0 || whisper_released,
    }
}

#[cfg(test)]
pub(crate) fn reset_local_whisper_usage_for_test() {
    let mut guard = match local_whisper_usage_state().lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    guard.last_used_at = None;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard, OnceLock};
    use std::time::Duration;

    fn lifecycle_test_guard() -> MutexGuard<'static, ()> {
        static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
        match GUARD.get_or_init(|| Mutex::new(())).lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    #[test]
    fn local_model_lifecycle_snapshot_reports_default_states() {
        let _guard = lifecycle_test_guard();
        crate::embedding::reset_fastembed_cache_for_test();
        crate::desktop_media::ocr::reset_ocr_cache_for_test();
        reset_local_whisper_usage_for_test();

        let snapshot = snapshot();

        assert_eq!(snapshot.fastembed.strategy, "cached");
        assert!(!snapshot.fastembed.loaded);
        assert_eq!(snapshot.fastembed.entry_count, 0);

        assert_eq!(snapshot.ocr.strategy, "cached");
        assert!(!snapshot.ocr.loaded);
        assert_eq!(snapshot.ocr.entry_count, 0);

        assert_eq!(snapshot.whisper.strategy, "ephemeral");
        assert!(!snapshot.whisper.loaded);
        assert_eq!(snapshot.whisper.entry_count, 0);
    }

    #[test]
    fn release_all_if_idle_is_noop_when_no_models_are_loaded() {
        let _guard = lifecycle_test_guard();
        crate::embedding::reset_fastembed_cache_for_test();
        crate::desktop_media::ocr::reset_ocr_cache_for_test();
        reset_local_whisper_usage_for_test();

        let summary = release_all_if_idle(Duration::from_secs(180));
        assert!(!summary.fastembed_released);
        assert_eq!(summary.ocr_released_count, 0);
        assert!(!summary.whisper_released);
        assert!(!summary.released_any);
    }

    #[cfg(all(
        any(target_os = "windows", target_os = "macos", target_os = "linux"),
        not(frb_expand)
    ))]
    #[test]
    fn release_all_if_idle_evicts_old_fastembed_and_ocr_entries() {
        let _guard = lifecycle_test_guard();
        crate::embedding::reset_fastembed_cache_for_test();
        crate::embedding::seed_fastembed_cache_for_test_with_last_used(Duration::from_secs(181));
        crate::desktop_media::ocr::reset_ocr_cache_for_test();
        crate::desktop_media::ocr::seed_ocr_cache_entry_for_test(
            "ocr:test:stale".to_string(),
            Duration::from_secs(181),
        );

        let summary = release_all_if_idle(Duration::from_secs(180));
        assert!(summary.fastembed_released);
        assert_eq!(summary.ocr_released_count, 1);
        assert!(summary.released_any);
    }

    #[cfg(all(
        any(target_os = "windows", target_os = "macos", target_os = "linux"),
        not(frb_expand)
    ))]
    #[test]
    fn release_all_if_idle_keeps_recent_fastembed_and_ocr_entries() {
        let _guard = lifecycle_test_guard();
        crate::embedding::reset_fastembed_cache_for_test();
        crate::embedding::seed_fastembed_cache_for_test_with_last_used(Duration::from_secs(60));
        crate::desktop_media::ocr::reset_ocr_cache_for_test();
        crate::desktop_media::ocr::seed_ocr_cache_entry_for_test(
            "ocr:test:fresh".to_string(),
            Duration::from_secs(60),
        );

        let summary = release_all_if_idle(Duration::from_secs(180));
        assert!(!summary.fastembed_released);
        assert_eq!(summary.ocr_released_count, 0);
        assert!(!summary.released_any);
    }

    #[test]
    fn whisper_lifecycle_strategy_remains_ephemeral_after_usage_mark() {
        let _guard = lifecycle_test_guard();
        reset_local_whisper_usage_for_test();
        mark_local_whisper_used();

        let snapshot = snapshot();
        assert_eq!(snapshot.whisper.strategy, "ephemeral");
        assert!(!snapshot.whisper.loaded);
        assert_eq!(snapshot.whisper.entry_count, 0);
        assert!(snapshot.whisper.last_used_ms_ago.is_some());
    }
}

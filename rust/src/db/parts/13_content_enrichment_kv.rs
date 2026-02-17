fn ensure_kv_defaults(conn: &Connection, defaults: &[(&str, String)]) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<()> {
        let mut stmt = conn.prepare(r#"INSERT OR IGNORE INTO kv(key, value) VALUES (?1, ?2)"#)?;
        for (key, value) in defaults {
            stmt.execute(params![key, value])?;
        }
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn ensure_content_enrichment_kv_defaults(conn: &Connection) -> Result<()> {
    let mb10 = 10i64 * 1024 * 1024;
    let gb2 = 2i64 * 1024 * 1024 * 1024;

    let defaults = vec![
        ("content_enrichment.url_fetch_enabled", "1".to_string()),
        (
            "content_enrichment.document_extract_enabled",
            "1".to_string(),
        ),
        (
            "content_enrichment.document_keep_original_max_bytes",
            (50i64 * 1024 * 1024).to_string(),
        ),
        (
            "content_enrichment.audio_transcribe_enabled",
            "1".to_string(),
        ),
        (
            "content_enrichment.audio_transcribe_engine",
            "whisper".to_string(),
        ),
        ("content_enrichment.video_extract_enabled", "1".to_string()),
        ("content_enrichment.video_proxy_enabled", "1".to_string()),
        (
            "content_enrichment.video_proxy_max_duration_ms",
            "3600000".to_string(),
        ),
        (
            "content_enrichment.video_proxy_max_bytes",
            "209715200".to_string(),
        ),
        ("content_enrichment.ocr_enabled", "1".to_string()),
        (
            "content_enrichment.ocr_engine_mode",
            "platform_native".to_string(),
        ),
        (
            "content_enrichment.ocr_language_hints",
            "device_plus_en".to_string(),
        ),
        ("content_enrichment.ocr_pdf_dpi", "180".to_string()),
        ("content_enrichment.ocr_pdf_auto_max_pages", "0".to_string()),
        ("content_enrichment.ocr_pdf_max_pages", "0".to_string()),
        (
            "content_enrichment.mobile_background_enabled",
            "1".to_string(),
        ),
        (
            "content_enrichment.mobile_background_requires_wifi",
            "1".to_string(),
        ),
        (
            "content_enrichment.mobile_background_requires_charging",
            "1".to_string(),
        ),
        ("storage_policy.auto_purge_enabled", "1".to_string()),
        (
            "storage_policy.auto_purge_keep_recent_days",
            "30".to_string(),
        ),
        ("storage_policy.auto_purge_max_cache_bytes", gb2.to_string()),
        (
            "storage_policy.auto_purge_min_candidate_bytes",
            mb10.to_string(),
        ),
        ("storage_policy.auto_purge_include_images", "0".to_string()),
    ];

    ensure_kv_defaults(conn, &defaults)
}

#[derive(Clone, Debug)]
pub struct ContentEnrichmentConfig {
    pub url_fetch_enabled: bool,
    pub document_extract_enabled: bool,
    pub document_keep_original_max_bytes: i64,
    pub audio_transcribe_enabled: bool,
    pub audio_transcribe_engine: String,
    pub video_extract_enabled: bool,
    pub video_proxy_enabled: bool,
    pub video_proxy_max_duration_ms: i64,
    pub video_proxy_max_bytes: i64,
    pub ocr_enabled: bool,
    pub ocr_engine_mode: String,
    pub ocr_language_hints: String,
    pub ocr_pdf_dpi: i64,
    pub ocr_pdf_auto_max_pages: i64,
    pub ocr_pdf_max_pages: i64,
    pub mobile_background_enabled: bool,
    pub mobile_background_requires_wifi: bool,
    pub mobile_background_requires_charging: bool,
}

#[derive(Clone, Debug)]
pub struct StoragePolicyConfig {
    pub auto_purge_enabled: bool,
    pub auto_purge_keep_recent_days: i64,
    pub auto_purge_max_cache_bytes: i64,
    pub auto_purge_min_candidate_bytes: i64,
    pub auto_purge_include_images: bool,
}

fn kv_bool_or(conn: &Connection, key: &str, default: bool) -> Result<bool> {
    let raw = kv_get_string(conn, key)?;
    Ok(match raw.as_deref() {
        None => default,
        Some(v) => v.trim() == "1",
    })
}

fn kv_i64_or(conn: &Connection, key: &str, default: i64) -> Result<i64> {
    let raw = kv_get_string(conn, key)?;
    match raw {
        None => Ok(default),
        Some(v) => Ok(v.trim().parse::<i64>().unwrap_or(default)),
    }
}

fn kv_string_or(conn: &Connection, key: &str, default: &str) -> Result<String> {
    Ok(kv_get_string(conn, key)?.unwrap_or_else(|| default.to_string()))
}

fn normalize_audio_transcribe_engine(engine: &str) -> &'static str {
    match engine.trim() {
        "" | "whisper" | "local_runtime" => "whisper",
        "multimodal_llm" => "multimodal_llm",
        _ => "whisper",
    }
}

fn normalize_ocr_engine_mode(mode: &str) -> &'static str {
    match mode.trim() {
        "" | "platform_native" | "auto" => "platform_native",
        "multimodal_llm" => "multimodal_llm",
        _ => "platform_native",
    }
}

pub fn get_content_enrichment_config(conn: &Connection) -> Result<ContentEnrichmentConfig> {
    let mb50 = 50i64 * 1024 * 1024;

    let url_fetch_enabled = kv_bool_or(conn, "content_enrichment.url_fetch_enabled", true)?;
    let document_extract_enabled =
        kv_bool_or(conn, "content_enrichment.document_extract_enabled", true)?;
    let document_keep_original_max_bytes = kv_i64_or(
        conn,
        "content_enrichment.document_keep_original_max_bytes",
        mb50,
    )?
    .max(0);

    let audio_transcribe_enabled =
        kv_bool_or(conn, "content_enrichment.audio_transcribe_enabled", true)?;
    let audio_transcribe_engine = kv_string_or(
        conn,
        "content_enrichment.audio_transcribe_engine",
        "whisper",
    )?;
    let audio_transcribe_engine =
        normalize_audio_transcribe_engine(&audio_transcribe_engine).to_string();

    let video_extract_enabled =
        kv_bool_or(conn, "content_enrichment.video_extract_enabled", false)?;
    let video_proxy_enabled = kv_bool_or(conn, "content_enrichment.video_proxy_enabled", true)?;
    let video_proxy_max_duration_ms = kv_i64_or(
        conn,
        "content_enrichment.video_proxy_max_duration_ms",
        3_600_000,
    )?
    .max(0);
    let video_proxy_max_bytes = kv_i64_or(
        conn,
        "content_enrichment.video_proxy_max_bytes",
        209_715_200,
    )?
    .max(0);

    let ocr_enabled = kv_bool_or(conn, "content_enrichment.ocr_enabled", true)?;
    let ocr_engine_mode = kv_string_or(
        conn,
        "content_enrichment.ocr_engine_mode",
        "platform_native",
    )?;
    let ocr_engine_mode = normalize_ocr_engine_mode(&ocr_engine_mode).to_string();
    let _ocr_language_hints = kv_string_or(
        conn,
        "content_enrichment.ocr_language_hints",
        "device_plus_en",
    )?;
    let ocr_language_hints = "device_plus_en".to_string();

    let _ocr_pdf_dpi = kv_i64_or(conn, "content_enrichment.ocr_pdf_dpi", 180)?.clamp(72, 600);
    let ocr_pdf_dpi = 180;
    let _ocr_pdf_auto_max_pages =
        kv_i64_or(conn, "content_enrichment.ocr_pdf_auto_max_pages", 0)?.max(0);
    let ocr_pdf_auto_max_pages = 0;
    let _ocr_pdf_max_pages = kv_i64_or(conn, "content_enrichment.ocr_pdf_max_pages", 0)?.max(0);
    let ocr_pdf_max_pages = 0;

    let mobile_background_enabled =
        kv_bool_or(conn, "content_enrichment.mobile_background_enabled", true)?;
    let mobile_background_requires_wifi = kv_bool_or(
        conn,
        "content_enrichment.mobile_background_requires_wifi",
        true,
    )?;
    let mobile_background_requires_charging = kv_bool_or(
        conn,
        "content_enrichment.mobile_background_requires_charging",
        true,
    )?;

    Ok(ContentEnrichmentConfig {
        url_fetch_enabled,
        document_extract_enabled,
        document_keep_original_max_bytes,
        audio_transcribe_enabled,
        audio_transcribe_engine,
        video_extract_enabled,
        video_proxy_enabled,
        video_proxy_max_duration_ms,
        video_proxy_max_bytes,
        ocr_enabled,
        ocr_engine_mode,
        ocr_language_hints,
        ocr_pdf_dpi,
        ocr_pdf_auto_max_pages,
        ocr_pdf_max_pages,
        mobile_background_enabled,
        mobile_background_requires_wifi,
        mobile_background_requires_charging,
    })
}

pub fn set_content_enrichment_config(
    conn: &Connection,
    config: &ContentEnrichmentConfig,
) -> Result<()> {
    let normalized_audio_engine =
        normalize_audio_transcribe_engine(&config.audio_transcribe_engine);
    let normalized_ocr_engine_mode = normalize_ocr_engine_mode(&config.ocr_engine_mode);

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<()> {
        kv_set_string(
            conn,
            "content_enrichment.url_fetch_enabled",
            if config.url_fetch_enabled { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.document_extract_enabled",
            if config.document_extract_enabled {
                "1"
            } else {
                "0"
            },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.document_keep_original_max_bytes",
            config
                .document_keep_original_max_bytes
                .clamp(0, i64::MAX)
                .to_string()
                .as_str(),
        )?;

        kv_set_string(
            conn,
            "content_enrichment.audio_transcribe_enabled",
            if config.audio_transcribe_enabled {
                "1"
            } else {
                "0"
            },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.audio_transcribe_engine",
            normalized_audio_engine,
        )?;

        kv_set_string(
            conn,
            "content_enrichment.video_extract_enabled",
            if config.video_extract_enabled {
                "1"
            } else {
                "0"
            },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.video_proxy_enabled",
            if config.video_proxy_enabled { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.video_proxy_max_duration_ms",
            config
                .video_proxy_max_duration_ms
                .clamp(0, i64::MAX)
                .to_string()
                .as_str(),
        )?;
        kv_set_string(
            conn,
            "content_enrichment.video_proxy_max_bytes",
            config
                .video_proxy_max_bytes
                .clamp(0, i64::MAX)
                .to_string()
                .as_str(),
        )?;

        kv_set_string(
            conn,
            "content_enrichment.ocr_enabled",
            if config.ocr_enabled { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.ocr_engine_mode",
            normalized_ocr_engine_mode,
        )?;
        kv_set_string(
            conn,
            "content_enrichment.ocr_language_hints",
            "device_plus_en",
        )?;

        kv_set_string(conn, "content_enrichment.ocr_pdf_dpi", "180")?;
        kv_set_string(conn, "content_enrichment.ocr_pdf_auto_max_pages", "0")?;
        kv_set_string(conn, "content_enrichment.ocr_pdf_max_pages", "0")?;

        kv_set_string(
            conn,
            "content_enrichment.mobile_background_enabled",
            if config.mobile_background_enabled {
                "1"
            } else {
                "0"
            },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.mobile_background_requires_wifi",
            if config.mobile_background_requires_wifi {
                "1"
            } else {
                "0"
            },
        )?;
        kv_set_string(
            conn,
            "content_enrichment.mobile_background_requires_charging",
            if config.mobile_background_requires_charging {
                "1"
            } else {
                "0"
            },
        )?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn get_storage_policy_config(conn: &Connection) -> Result<StoragePolicyConfig> {
    let mb10 = 10i64 * 1024 * 1024;
    let gb2 = 2i64 * 1024 * 1024 * 1024;

    let auto_purge_enabled = kv_bool_or(conn, "storage_policy.auto_purge_enabled", true)?;
    let auto_purge_keep_recent_days =
        kv_i64_or(conn, "storage_policy.auto_purge_keep_recent_days", 30)?.max(0);
    let auto_purge_max_cache_bytes =
        kv_i64_or(conn, "storage_policy.auto_purge_max_cache_bytes", gb2)?.max(0);
    let auto_purge_min_candidate_bytes =
        kv_i64_or(conn, "storage_policy.auto_purge_min_candidate_bytes", mb10)?.max(0);
    let auto_purge_include_images =
        kv_bool_or(conn, "storage_policy.auto_purge_include_images", false)?;

    Ok(StoragePolicyConfig {
        auto_purge_enabled,
        auto_purge_keep_recent_days,
        auto_purge_max_cache_bytes,
        auto_purge_min_candidate_bytes,
        auto_purge_include_images,
    })
}

pub fn set_storage_policy_config(conn: &Connection, config: &StoragePolicyConfig) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<()> {
        kv_set_string(
            conn,
            "storage_policy.auto_purge_enabled",
            if config.auto_purge_enabled { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            "storage_policy.auto_purge_keep_recent_days",
            config
                .auto_purge_keep_recent_days
                .clamp(0, 10_000)
                .to_string()
                .as_str(),
        )?;
        kv_set_string(
            conn,
            "storage_policy.auto_purge_max_cache_bytes",
            config
                .auto_purge_max_cache_bytes
                .clamp(0, i64::MAX)
                .to_string()
                .as_str(),
        )?;
        kv_set_string(
            conn,
            "storage_policy.auto_purge_min_candidate_bytes",
            config
                .auto_purge_min_candidate_bytes
                .clamp(0, i64::MAX)
                .to_string()
                .as_str(),
        )?;
        kv_set_string(
            conn,
            "storage_policy.auto_purge_include_images",
            if config.auto_purge_include_images {
                "1"
            } else {
                "0"
            },
        )?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

//
// Do not put code in `mod.rs`, but put in e.g. `simple.rs`.
//

pub mod ask_scope;
pub mod attachments;
#[cfg(not(target_family = "wasm"))]
pub mod audio_transcribe;
#[cfg(target_family = "wasm")]
#[path = "audio_transcribe_wasm.rs"]
pub mod audio_transcribe;
pub mod content_enrichment;
pub mod content_extract;
pub mod core;
pub mod desktop_media;
pub mod detached_ask;
pub mod embedding_lifecycle;
pub mod external_import;
pub mod media_annotation;
pub mod migration_archive;
pub mod oplog_maintenance;
pub mod remote_embedding_bootstrap;
pub mod semantic_parse_enhancement;
pub mod semantic_parse_jobs;
pub mod simple;
#[cfg(not(target_family = "wasm"))]
pub mod sync_diagnostics;
#[cfg(target_family = "wasm")]
#[path = "sync_diagnostics_wasm.rs"]
pub mod sync_diagnostics;
#[cfg(not(target_family = "wasm"))]
pub mod sync_progress;
#[cfg(target_family = "wasm")]
#[path = "sync_progress_wasm.rs"]
pub mod sync_progress;
pub mod tags;
pub mod todo_followup_generation;
pub mod web_sync;

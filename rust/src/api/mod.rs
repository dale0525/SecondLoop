//
// Do not put code in `mod.rs`, but put in e.g. `simple.rs`.
//

pub mod ask_scope;
pub mod attachments;
pub mod audio_transcribe;
pub mod content_enrichment;
pub mod content_extract;
pub mod core;
pub mod desktop_media;
pub mod detached_ask;
pub mod embedding_lifecycle;
pub mod external_import;
pub mod knowledge;
pub mod media_annotation;
pub mod migration_archive;
pub mod oplog_maintenance;
pub mod simple;
pub mod sync_diagnostics;
pub mod sync_progress;
pub mod tags;

#[cfg(test)]
mod knowledge_tests;

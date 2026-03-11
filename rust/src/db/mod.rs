// This module is split into smaller files to keep each file under ~1000 lines.
// The pieces are `include!`'d so everything remains in `crate::db`.

include!("parts/01_prelude.rs");
include!("parts/01_kv_and_oplog.rs");
include!("parts/02_migrate.rs");
include!("parts/13_content_enrichment_kv.rs");
include!("parts/03_conversations_messages.rs");
include!("parts/04_profiles_llm_usage.rs");
include!("parts/05_embeddings_active.rs");
include!("parts/06_attachment_reads_and_embeddings_processing.rs");
include!("parts/07_messages_and_similarity.rs");
include!("parts/08_attachments_core.rs");
include!("parts/08_attachment_metadata.rs");
include!("parts/09_attachment_jobs.rs");
include!("parts/14_content_extract_jobs.rs");
include!("parts/10_todos.rs");
include!("parts/15_todo_recurrence.rs");
include!("parts/11_events.rs");
include!("parts/12_media_annotation_config.rs");
include!("parts/16_tags.rs");
include!("parts/17_tags_manual_and_delete.rs");
include!("parts/18_tag_merge_feedback.rs");
include!("parts/19_suggested_tags.rs");
include!("parts/20_message_tag_autofill.rs");
include!("parts/21_attachment_chunk_index.rs");
include!("parts/22_detached_ask_completion.rs");
include!("parts/23_external_readonly_db.rs");
include!("parts/24_external_readonly_import_parser.rs");
include!("parts/24_external_readonly_import.rs");
include!("parts/25_external_readonly_search.rs");
include!("parts/26_external_readonly_phase_b.rs");
include!("parts/27_knowledge_index.rs");

#[cfg(test)]
mod semantic_parse_jobs_tests;

#[cfg(test)]
mod cloud_media_backup_tests;

#[cfg(test)]
mod content_extract_jobs_tests;

#[cfg(test)]
mod message_tag_autofill_tests;

#[cfg(test)]
mod tag_optimization_tests;

#[cfg(test)]
mod todo_status_auto_schedule_tests;

#[cfg(test)]
mod detached_ask_completion_tests;

#[cfg(test)]
mod external_import_tests;

#[cfg(test)]
mod external_import_phase_b_tests;

#[cfg(test)]
mod knowledge_index_tests;

#[cfg(test)]
mod knowledge_compat_tests;

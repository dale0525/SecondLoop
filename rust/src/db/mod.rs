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
include!("parts/17_topic_threads.rs");
include!("parts/18_tag_merge_feedback.rs");
include!("parts/19_suggested_tags.rs");
include!("parts/20_message_tag_autofill.rs");

#[cfg(test)]
mod semantic_parse_jobs_tests;

#[cfg(test)]
mod cloud_media_backup_tests;

#[cfg(test)]
mod content_extract_jobs_tests;

#[cfg(test)]
mod message_tag_autofill_tests;

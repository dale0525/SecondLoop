pub const KNOWLEDGE_SCHEMA_VERSION: i64 = 1;
pub const KNOWLEDGE_NORMALIZATION_VERSION: i64 = 1;
pub const KNOWLEDGE_SEGMENTATION_VERSION: i64 = 1;
pub const KNOWLEDGE_EMBEDDING_POLICY_VERSION: i64 = 1;
pub const KNOWLEDGE_RETRIEVAL_POLICY_VERSION: i64 = 1;

pub mod chunk;
pub mod embedding_batch;
pub mod index_jobs;
pub mod models;
pub mod normalize;
pub mod rebuild;
pub mod segment;
pub mod source_adapters;

pub use chunk::{build_chunk_units, build_section_units, build_segment_units};
pub use index_jobs::{
    ensure_knowledge_rebuild_requested, process_pending_knowledge_index_jobs_active,
};
pub use models::{
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeIndexStatus, KnowledgeOriginType,
    KnowledgeRole, KnowledgeSourceKind, KnowledgeUnit, KnowledgeUnitKind, KnowledgeVersionSet,
};
pub use normalize::normalize_text_for_source;
pub use rebuild::{
    cancel_knowledge_rebuild, list_knowledge_documents, list_knowledge_units,
    read_knowledge_index_status,
};
pub use segment::{segment_document_text, SegmentDraft};
pub use source_adapters::{collect_source_knowledge_documents, visit_source_knowledge_documents};

#[cfg(test)]
mod chunk_tests;
#[cfg(test)]
mod embedding_batch_tests;
#[cfg(test)]
mod index_jobs_failure_tests;
#[cfg(test)]
mod index_jobs_finalize_tests;
#[cfg(test)]
mod index_jobs_pagination_tests;
#[cfg(test)]
mod index_jobs_tests;
#[cfg(test)]
mod models_tests;
#[cfg(test)]
mod normalize_tests;
#[cfg(test)]
mod rebuild_tests;
#[cfg(test)]
mod source_adapters_tests;

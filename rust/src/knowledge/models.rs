use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeAnchorSet {
    pub message_id: Option<String>,
    pub conversation_id: Option<String>,
    pub attachment_sha256: Option<String>,
    pub page_index: Option<i64>,
    pub frame_index: Option<i64>,
    pub start_ms: Option<i64>,
    pub end_ms: Option<i64>,
    pub speaker: Option<String>,
    pub section_label: Option<String>,
    pub source_filename: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeOriginType {
    Message,
    Attachment,
    ImportedExternal,
    Generated,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeSourceKind {
    RawText,
    ExtractedText,
    ReadableText,
    OcrText,
    Transcript,
    ImageUnderstanding,
    VideoKeyframeUnderstanding,
    Metadata,
    Summary,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeRole {
    Title,
    Summary,
    Body,
    Metadata,
    Caption,
    Evidence,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeUnitKind {
    Section,
    Segment,
    Chunk,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeQueryScope {
    All,
    Conversation,
    Document,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeRetrievalLayer {
    Document,
    Section,
    Chunk,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeVersionSet {
    pub schema_version: i64,
    pub normalization_version: i64,
    pub segmentation_version: i64,
    pub embedding_policy_version: i64,
    pub retrieval_policy_version: i64,
}

impl KnowledgeVersionSet {
    pub fn current() -> Self {
        Self {
            schema_version: crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            normalization_version: crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            segmentation_version: crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            embedding_policy_version: crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            retrieval_policy_version: crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ContentKnowledgeDocument {
    pub document_id: String,
    pub origin_type: KnowledgeOriginType,
    pub source_kind: KnowledgeSourceKind,
    pub role: KnowledgeRole,
    pub language: Option<String>,
    pub quality_score: f64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub versions: KnowledgeVersionSet,
    pub anchors: KnowledgeAnchorSet,
    pub title: Option<String>,
    pub summary: Option<String>,
    pub raw_text: String,
    pub normalized_text: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeUnit {
    pub unit_id: String,
    pub document_id: String,
    pub parent_unit_id: Option<String>,
    pub unit_kind: KnowledgeUnitKind,
    pub source_kind: KnowledgeSourceKind,
    pub role: KnowledgeRole,
    pub ordinal: i64,
    pub token_count: i64,
    pub raw_text: String,
    pub normalized_text: String,
    pub anchors: KnowledgeAnchorSet,
    pub prev_unit_id: Option<String>,
    pub next_unit_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeIndexStatus {
    pub status: String,
    pub rebuild_required: bool,
    pub stale_reason: Option<String>,
    pub last_error: Option<String>,
    pub last_rebuild_started_at_ms: Option<i64>,
    pub last_rebuild_completed_at_ms: Option<i64>,
    pub current_document_id: Option<String>,
    pub current_stage: Option<String>,
    pub documents_indexed: i64,
    pub units_indexed: i64,
    pub embeddings_indexed: i64,
    pub total_documents: i64,
    pub last_indexed_model_name: Option<String>,
    pub last_indexed_dim: Option<i64>,
    pub versions: KnowledgeVersionSet,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeSearchResult {
    pub document_id: String,
    pub unit_id: Option<String>,
    pub unit_kind: Option<KnowledgeUnitKind>,
    pub layer: KnowledgeRetrievalLayer,
    pub source_kind: KnowledgeSourceKind,
    pub role: KnowledgeRole,
    pub title: Option<String>,
    pub summary: Option<String>,
    pub snippet: String,
    pub score: f64,
    pub semantic_score: f64,
    pub lexical_score: f64,
    pub anchors: KnowledgeAnchorSet,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeContextBlock {
    pub document_id: String,
    pub unit_id: Option<String>,
    pub unit_kind: Option<KnowledgeUnitKind>,
    pub source_kind: KnowledgeSourceKind,
    pub role: KnowledgeRole,
    pub anchors: KnowledgeAnchorSet,
    pub score: f64,
    pub rendered_text: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeViewerDocument {
    pub document: ContentKnowledgeDocument,
    pub total_units: i64,
    pub section_count: i64,
    pub chunk_count: i64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeViewerPage {
    pub document_id: String,
    pub unit_kind: Option<KnowledgeUnitKind>,
    pub offset: i64,
    pub limit: i64,
    pub total: i64,
    pub units: Vec<KnowledgeUnit>,
}

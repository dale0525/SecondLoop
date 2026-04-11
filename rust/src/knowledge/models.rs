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
pub enum GeneratedMemoryKind {
    Profile,
    Preference,
    Event,
    Pattern,
}

impl GeneratedMemoryKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Profile => "profile",
            Self::Preference => "preference",
            Self::Event => "event",
            Self::Pattern => "pattern",
        }
    }
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeMemoryStatus {
    Confirmed,
    Inferred,
    MaybeOutdated,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeMemorySection {
    Preference,
    Person,
    Project,
    Topic,
    RecentEvent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeMemoryFeedback {
    pub status: Option<KnowledgeMemoryStatus>,
    pub use_for_ask_ai: bool,
    pub is_deleted: bool,
    pub marked_inaccurate: bool,
    pub corrected_title: Option<String>,
    pub corrected_summary: Option<String>,
    pub updated_at_ms: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeMemoryDisplay {
    pub section: KnowledgeMemorySection,
    pub source_count: i64,
    pub status: KnowledgeMemoryStatus,
}

impl Default for KnowledgeMemoryFeedback {
    fn default() -> Self {
        Self {
            status: None,
            use_for_ask_ai: true,
            is_deleted: false,
            marked_inaccurate: false,
            corrected_title: None,
            corrected_summary: None,
            updated_at_ms: None,
        }
    }
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
    pub memory_display: Option<KnowledgeMemoryDisplay>,
    pub memory_feedback: KnowledgeMemoryFeedback,
}

pub fn infer_memory_status(
    document_id: &str,
    updated_at_ms: i64,
    feedback: &KnowledgeMemoryFeedback,
) -> KnowledgeMemoryStatus {
    if let Some(status) = feedback.status {
        return status;
    }
    let now_ms = crate::knowledge::usage::now_ms();
    let age_ms = now_ms.saturating_sub(updated_at_ms);
    if document_id.starts_with("generated:event:") && age_ms > 30_i64 * 24 * 60 * 60 * 1000 {
        return KnowledgeMemoryStatus::MaybeOutdated;
    }
    KnowledgeMemoryStatus::Inferred
}

pub fn infer_generated_memory_section(
    document_id: &str,
    title: Option<&str>,
    summary: Option<&str>,
    raw_text: &str,
) -> Option<KnowledgeMemorySection> {
    if document_id.starts_with("generated:preference:") {
        return Some(KnowledgeMemorySection::Preference);
    }
    if document_id.starts_with("generated:event:") {
        return Some(KnowledgeMemorySection::RecentEvent);
    }

    let project_signal = [
        document_id,
        title.unwrap_or_default(),
        summary.unwrap_or_default(),
        raw_text,
    ]
    .join("\n")
    .to_lowercase();

    if document_id.starts_with("generated:profile:") {
        if looks_like_project_memory(&project_signal) {
            return Some(KnowledgeMemorySection::Project);
        }
        return Some(KnowledgeMemorySection::Person);
    }

    if document_id.starts_with("generated:pattern:") {
        if document_id == "generated:pattern:active-task-focus"
            || looks_like_project_memory(&project_signal)
        {
            return Some(KnowledgeMemorySection::Project);
        }
        return Some(KnowledgeMemorySection::Topic);
    }

    None
}

fn looks_like_project_memory(value: &str) -> bool {
    const SIGNALS: [&str; 19] = [
        "project",
        "prototype",
        "launch",
        "roadmap",
        "build",
        "product",
        "app",
        "rollout",
        "项目",
        "產品",
        "产品",
        "原型",
        "上线",
        "發布",
        "发布",
        "路線圖",
        "路线图",
        "版本",
        "迭代",
    ];
    SIGNALS.iter().any(|signal| value.contains(signal))
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeDebugStats {
    pub total_documents: i64,
    pub generated_documents: i64,
    pub source_documents: i64,
    pub summary_documents: i64,
    pub preference_documents: i64,
    pub profile_documents: i64,
    pub event_documents: i64,
    pub pattern_documents: i64,
    pub usage_stat_documents: i64,
    pub last_synthesis_at_ms: Option<i64>,
    pub last_retrieved_at_ms: Option<i64>,
    pub generated_memory_retrieval_enabled: bool,
    pub hotness_rerank_enabled: bool,
    pub session_digest_enabled: bool,
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

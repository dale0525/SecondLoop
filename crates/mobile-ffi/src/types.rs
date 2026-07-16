use agent_runtime::skill_management::{SkillActionFacts, SkillPackageStatus};
use agent_runtime::skill_policy::{ActorContext, SkillManagementPolicy};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fmt;
use zeroize::Zeroize;

#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileInitConfig {
    pub app_data_dir: String,
    #[serde(default)]
    pub app_package_dir: Option<String>,
    pub cache_dir: String,
    pub database_path: String,
    pub builtin_skills_dir: String,
    pub managed_skills_dir: String,
    pub staging_skills_dir: String,
    pub quarantine_skills_dir: String,
    pub skill_policy: SkillManagementPolicy,
    pub actor_context: ActorContext,
    pub platform: String,
    pub capabilities: Vec<String>,
    #[serde(default, skip_serializing)]
    pub storage_protection_key_hex: Option<String>,
}

impl fmt::Debug for MobileInitConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("MobileInitConfig")
            .field("app_data_dir", &self.app_data_dir)
            .field("app_package_dir", &self.app_package_dir)
            .field("cache_dir", &self.cache_dir)
            .field("database_path", &self.database_path)
            .field("builtin_skills_dir", &self.builtin_skills_dir)
            .field("managed_skills_dir", &self.managed_skills_dir)
            .field("staging_skills_dir", &self.staging_skills_dir)
            .field("quarantine_skills_dir", &self.quarantine_skills_dir)
            .field("skill_policy", &self.skill_policy)
            .field("actor_context", &self.actor_context)
            .field("platform", &self.platform)
            .field("capabilities", &self.capabilities)
            .field(
                "storage_protection_key_configured",
                &self.storage_protection_key_hex.is_some(),
            )
            .finish()
    }
}

impl Drop for MobileInitConfig {
    fn drop(&mut self) {
        if let Some(key) = &mut self.storage_protection_key_hex {
            key.zeroize();
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileDiagnostics {
    pub app_id: String,
    pub app_version: String,
    pub app_display_name: String,
    pub platform: String,
    pub capabilities: Vec<String>,
    pub database_ready: bool,
    pub storage_protection_state: String,
    pub skills_ready: bool,
    pub model_configured: bool,
    pub skill_management_mode: String,
    pub active_snapshot_generation: u64,
    pub quarantined_count: usize,
    pub last_reload_status: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileSessionDto {
    pub id: String,
    pub title: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileMessageDto {
    pub id: String,
    pub session_id: String,
    pub role: String,
    pub content: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileSkillDto {
    pub package_id: String,
    pub display_name: String,
    pub version: String,
    pub source_layer: String,
    pub status: String,
    pub available: bool,
    pub reason: String,
    pub active_revision_id: Option<String>,
    pub manageable: bool,
    pub built_in_collision: bool,
    pub effective: Option<SkillPackageStatus>,
    pub managed: Option<SkillPackageStatus>,
    pub actions: SkillActionFacts,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileModelConfigDto {
    pub provider_id: String,
    pub provider_name: String,
    pub endpoint_type: String,
    pub base_url: String,
    pub model_name: String,
    pub secret_id: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileTurnDto {
    pub assistant_text: String,
}

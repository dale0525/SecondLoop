#![cfg_attr(test, allow(deprecated))]

pub mod api;
mod api_foundations;
mod attachment_api;
mod automation_api;
mod conversation_api;
pub mod data_protection;
mod data_protection_api;
mod dev_api;
pub mod dev_skills;
mod foundation_api;
pub mod local_transport;
mod oauth_api;
pub mod owner_api;
pub mod skill_release;
mod task_api;
mod tenant_attempt;
mod tenant_initialization;
#[cfg(test)]
mod tenant_initialization_tests;
pub mod tenant_skills;
mod turn_api;

#[cfg(test)]
mod api_attachment_tests;
#[cfg(test)]
mod api_data_protection_tests;
#[cfg(test)]
mod skill_release_tests;
#[cfg(test)]
mod tenant_skills_tests;

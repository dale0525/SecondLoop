#![cfg_attr(test, allow(deprecated))]

pub mod api;
mod api_foundations;
mod attachment_api;
mod automation_api;
mod conversation_api;
pub mod data_protection;
mod data_protection_api;
mod dev_api;
mod dev_skill_authoring;
mod dev_skill_authoring_error;
pub mod dev_skills;
pub mod developer_control_plane;
mod developer_control_plane_api;
mod developer_control_plane_deployment;
mod developer_control_plane_oauth;
mod developer_firebase;
mod developer_firebase_models;
mod developer_firebase_oauth;
mod developer_firebase_refresh;
mod developer_gateway_projection;
mod developer_sensitive_store;
mod event_visibility;
pub mod firebase_identity_store;
mod foundation_api;
pub mod identity_api;
pub mod local_transport;
mod model_access_api;
mod oauth_api;
pub mod owner_api;
pub mod provider_catalog;
pub mod skill_release;
mod structured_content_api;
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
mod developer_control_plane_tests;
#[cfg(test)]
mod skill_release_tests;
#[cfg(test)]
mod tenant_skills_tests;

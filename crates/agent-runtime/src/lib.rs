#![cfg_attr(test, allow(deprecated))]

pub mod app_definition;
pub mod app_manifest;
pub mod approval;
pub mod attachment_tools;
pub mod attachments;
pub mod automation;
pub mod automation_tools;
pub mod calendar;
pub mod calendar_action_envelope;
pub mod calendar_actions;
pub mod calendar_connector_transport;
pub mod connector;
pub mod connector_ledger;
pub mod connector_tools;
pub mod contacts;
pub mod contacts_action_envelope;
pub mod contacts_actions;
pub mod contacts_connector_transport;
pub mod context;
mod conversation_migration;
pub mod credential;
pub mod credential_file;
pub mod credential_sqlite;
pub mod data_protection;
pub mod documents;
pub mod durable_run;
pub mod event_persistence;
pub mod events;
pub mod foundation_action_envelope;
pub mod foundation_actions;
pub mod instructions;
pub mod mail;
pub mod mail_action_envelope;
pub mod mail_attachments;
pub mod mail_connector_transport;
pub mod mail_fake;
#[cfg(not(target_os = "android"))]
pub mod mail_imap_smtp;
#[cfg(not(target_os = "android"))]
pub mod mail_imap_smtp_accounts;
pub mod memory;
pub mod memory_lifecycle;
pub mod memory_sqlite;
pub mod memory_tools;
pub mod messaging;
pub mod mobile_host;
pub mod model_config;
pub mod notes;
pub mod oauth;
mod oauth_sqlite;
pub mod platform;
pub mod policy;
pub mod prompt_composer;
pub mod scheduler;
pub mod session;
pub mod skill;
pub mod skill_authoring;
pub mod skill_availability;
pub mod skill_bundle;
mod skill_bundle_publisher_lock;
pub mod skill_catalog;
mod skill_entry_resource;
pub mod skill_management;
pub mod skill_management_tools;
pub mod skill_manager;
pub mod skill_migration;
pub mod skill_package;
pub mod skill_policy;
pub mod skill_recovery;
pub mod skill_resolver;
pub mod skill_resource;
mod skill_runtime_source;
pub mod skill_security;
pub mod skill_snapshot;
pub mod skill_source;
pub mod skill_state;
mod skill_state_activation;
mod skill_state_cleanup;
mod skill_state_compensation;
mod skill_state_leases;
mod skill_state_lifecycle;
mod skill_state_management;
mod skill_state_migration;
mod skill_state_recovery;
mod skill_state_revision_cas;
mod skill_state_rows;
mod skill_state_startup;
mod skill_state_transactions;
mod skill_state_upgrade;
pub mod skill_store;
mod skill_store_atomic_write;
mod skill_store_authoring;
mod skill_store_cleanup;
mod skill_store_directory_ops;
mod skill_store_draft;
mod skill_store_execution;
mod skill_store_faults;
mod skill_store_fs;
mod skill_store_fs_types;
mod skill_store_inspection;
mod skill_store_locks;
mod skill_store_operations;
mod skill_store_path_prepare;
mod skill_store_prepared_fs;
mod skill_store_public_types;
mod skill_store_recovery;
mod skill_store_revision_cleanup;
mod skill_store_secure_fs;
mod skill_store_secure_fs_faults;
mod skill_store_secure_roots;
mod skill_store_secure_snapshot;
mod skill_store_startup;
mod skill_store_transfer;
mod skill_store_windows;
mod skill_store_windows_directory_create;
mod skill_verified;
pub mod storage;
pub mod storage_protection;
pub mod structured_content;
pub mod subagent;
pub mod task_sqlite;
pub mod task_tools;
pub mod tasks;
pub mod tools;
pub mod turn;
pub mod turn_request;
pub mod turn_storage;
pub mod vfs;
pub mod web_research;

#[cfg(test)]
mod skill_package_tests;

#[cfg(test)]
mod skill_bundle_tests;

#[cfg(test)]
mod skill_bundle_review_tests;

#[cfg(test)]
mod skill_bundle_final_review_tests;

#[cfg(test)]
mod skill_policy_tests;

#[cfg(test)]
mod runtime_tool_identity_tests;
#[cfg(test)]
mod skill_management_read_rereview_tests;
#[cfg(test)]
mod skill_management_tests;
#[cfg(test)]
mod skill_recovery_cleanup_tests;
#[cfg(test)]
mod skill_recovery_final_circuit_tests;
#[cfg(test)]
mod skill_recovery_residue_tests;
#[cfg(test)]
mod skill_recovery_review_lifecycle_tests;
#[cfg(test)]
mod skill_recovery_review_runtime_tests;
#[cfg(test)]
mod skill_recovery_terminal_authority_tests;
#[cfg(test)]
mod skill_recovery_terminal_tests;
#[cfg(test)]
mod skill_recovery_tests;
#[cfg(test)]
mod skill_rollback_cleanup_tests;
#[cfg(test)]
mod turn_managed_lease_tests;
#[cfg(test)]
mod turn_observer_tests;

#[cfg(test)]
mod skill_authoring_activation_tests;
#[cfg(test)]
mod skill_authoring_fix2_stage_tests;
#[cfg(test)]
mod skill_authoring_fix2_tests;
#[cfg(test)]
mod skill_authoring_fix3_tests;
#[cfg(test)]
mod skill_authoring_terminal_tests;
#[cfg(test)]
mod skill_authoring_tests;
#[cfg(test)]
mod skill_authoring_transfer_tests;

#[cfg(test)]
mod skill_authoring_atomicity_tests;

#[cfg(test)]
mod skill_store_authoring_race_tests;

#[cfg(test)]
mod skill_manager_convergence_tests;
#[cfg(test)]
mod skill_manager_tests;

#[cfg(test)]
mod skill_resolver_tests;

#[cfg(test)]
mod skill_runtime_tests;

#[cfg(test)]
mod skill_entry_resource_tests;

#[cfg(test)]
mod skill_state_tests;

#[cfg(test)]
mod skill_state_management_tests;

#[cfg(test)]
mod skill_state_lifecycle_tests;

#[cfg(test)]
mod skill_state_cas_tests;

#[cfg(test)]
mod skill_state_migration_tests;

#[cfg(test)]
mod skill_state_row_snapshot_tests;

#[cfg(test)]
mod skill_store_tests;

#[cfg(test)]
mod skill_store_failure_tests;

#[cfg(test)]
mod skill_store_concurrency_tests;

#[cfg(test)]
mod skill_store_security_tests;

#[cfg(test)]
mod skill_store_write_recovery_tests;

#[cfg(test)]
mod skill_store_lock_tests;

#[cfg(test)]
mod skill_store_compensation_tests;

#[cfg(test)]
mod managed_skill_source_tests;

#[cfg(test)]
mod managed_skill_source_limits_tests;

#[cfg(test)]
mod managed_verified_content_tests;

#[cfg(test)]
mod skill_store_windows_contract_tests;

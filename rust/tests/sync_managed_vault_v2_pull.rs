use base64::Engine as _;
use rusqlite::OptionalExtension;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::blob_repair::{self, BlobRepairKind};

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::{managed_vault_v2_scope_id, start_mock_v2_server};

#[path = "sync_managed_vault_v2_pull/artifact_backfill.rs"]
mod artifact_backfill;
#[path = "sync_managed_vault_v2_pull/repair_guards.rs"]
mod repair_guards;
#[path = "sync_managed_vault_v2_pull/state_recovery.rs"]
mod state_recovery;

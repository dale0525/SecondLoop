use rusqlite::OptionalExtension;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use std::fs;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::{managed_vault_v2_scope_id, start_mock_v2_server};

fn oplog_count(conn: &rusqlite::Connection) -> i64 {
    conn.query_row(r#"SELECT COUNT(*) FROM oplog"#, [], |row| row.get(0))
        .expect("count oplog")
}

#[path = "sync_managed_vault_v2_push/attachments.rs"]
mod attachments;
#[path = "sync_managed_vault_v2_push/cursor_progress.rs"]
mod cursor_progress;
#[path = "sync_managed_vault_v2_push/retention.rs"]
mod retention;
#[path = "sync_managed_vault_v2_push/roundtrip_and_recovery.rs"]
mod roundtrip_and_recovery;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SqliteOpenPragmas {
    journal_mode: &'static str,
    synchronous: Option<&'static str>,
}

fn sqlite_open_pragmas_for_mode(
    mode: crate::platform::sqlite_runtime::SqlitePersistenceMode,
) -> SqliteOpenPragmas {
    match mode {
        crate::platform::sqlite_runtime::SqlitePersistenceMode::RelaxedIdb => SqliteOpenPragmas {
            journal_mode: "DELETE",
            synchronous: Some("OFF"),
        },
        crate::platform::sqlite_runtime::SqlitePersistenceMode::NativeFilesystem
        | crate::platform::sqlite_runtime::SqlitePersistenceMode::OpfsSAHPool => {
            SqliteOpenPragmas {
                journal_mode: "WAL",
                synchronous: None,
            }
        }
    }
}

fn apply_sqlite_open_pragmas(conn: &Connection) -> Result<()> {
    let pragmas = sqlite_open_pragmas_for_mode(crate::platform::sqlite_runtime::sqlite_persistence_mode());
    conn.busy_timeout(Duration::from_millis(5_000))?;
    conn.pragma_update(None, "journal_mode", pragmas.journal_mode)?;
    if let Some(synchronous) = pragmas.synchronous {
        conn.pragma_update(None, "synchronous", synchronous)?;
    }
    Ok(())
}

fn apply_recent_main_db_migrations(conn: &Connection, mut user_version: i64) -> Result<i64> {
    if user_version < 30 {
        migrate_from_v29_to_v30(conn)?;
        user_version = 30;
    }

    if user_version < 31 {
        migrate_from_v30_to_v31(conn)?;
        user_version = 31;
    }

    if user_version < 32 {
        migrate_from_v31_to_v32(conn)?;
        user_version = 32;
    }

    if user_version < 33 {
        migrate_from_v32_to_v33(conn)?;
        user_version = 33;
    }

    if user_version < 34 {
        migrate_from_v33_to_v34(conn)?;
        user_version = 34;
    }

    if user_version < 35 {
        migrate_from_v34_to_v35(conn)?;
        user_version = 35;
    }

    if user_version < 36 {
        migrate_from_v35_to_v36(conn)?;
        user_version = 36;
    }

    if user_version < 37 {
        migrate_from_v36_to_v37(conn)?;
        user_version = 37;
    }

    if user_version < 38 {
        migrate_from_v37_to_v38(conn)?;
        user_version = 38;
    }

    if user_version < 39 {
        migrate_from_v38_to_v39(conn)?;
        user_version = 39;
    }

    if user_version < 40 {
        migrate_from_v39_to_v40(conn)?;
        user_version = 40;
    }

    if user_version < 41 {
        migrate_from_v40_to_v41(conn)?;
        user_version = 41;
    }

    if user_version < 42 {
        migrate_from_v41_to_v42(conn)?;
        user_version = 42;
    }

    if user_version < 43 {
        migrate_from_v42_to_v43(conn)?;
        user_version = 43;
    }

    if user_version < 44 {
        migrate_from_v43_to_v44(conn)?;
        user_version = 44;
    }

    if user_version < 45 {
        migrate_from_v44_to_v45(conn)?;
        user_version = 45;
    }

    if user_version < 46 {
        migrate_from_v45_to_v46(conn)?;
        user_version = 46;
    }

    if user_version < 47 {
        migrate_from_v46_to_v47(conn)?;
        user_version = 47;
    }

    if user_version < 48 {
        migrate_from_v47_to_v48(conn)?;
        user_version = 48;
    }

    if user_version < 49 {
        migrate_from_v48_to_v49(conn)?;
        user_version = 49;
    }

    if user_version < 50 {
        migrate_from_v49_to_v50(conn)?;
        user_version = 50;
    }

    if user_version < 51 {
        migrate_from_v50_to_v51(conn)?;
        user_version = 51;
    }

    Ok(user_version)
}

pub fn open(app_dir: &Path) -> Result<Connection> {
    crate::platform::sqlite_runtime::ensure_sqlite_parent_dir(app_dir)?;
    vector::register_sqlite_vec()?;
    let conn = Connection::open(db_path(app_dir))?;
    apply_sqlite_open_pragmas(&conn)?;
    migrate(&conn)?;
    ensure_todo_manual_nudge_columns(&conn)?;
    ensure_content_enrichment_kv_defaults(&conn)?;
    Ok(conn)
}

fn migrate_from_v50_to_v51(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS secretary_memory_proposals (
  id TEXT PRIMARY KEY,
  source_message_id TEXT,
  kind TEXT NOT NULL,
  title BLOB NOT NULL,
  body BLOB NOT NULL,
  confidence REAL NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending',
  source_refs_json BLOB,
  action_hint TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  accepted_at_ms INTEGER,
  dismissed_at_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_secretary_memory_proposals_state_updated
  ON secretary_memory_proposals(state, updated_at_ms DESC, created_at_ms DESC);
CREATE INDEX IF NOT EXISTS idx_secretary_memory_proposals_source_message
  ON secretary_memory_proposals(source_message_id, state);

CREATE TABLE IF NOT EXISTS planning_outputs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  title BLOB NOT NULL,
  body BLOB NOT NULL,
  items_json BLOB NOT NULL,
  source_refs_json BLOB,
  route TEXT NOT NULL,
  state TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER,
  dismissed_at_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_planning_outputs_kind_state_updated
  ON planning_outputs(kind, state, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS idx_planning_outputs_expires
  ON planning_outputs(expires_at_ms);

CREATE TABLE IF NOT EXISTS secretary_runs (
  id TEXT PRIMARY KEY,
  trigger_kind TEXT NOT NULL,
  route TEXT NOT NULL,
  status TEXT NOT NULL,
  input_summary BLOB,
  output_summary BLOB,
  error BLOB,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_secretary_runs_status_updated
  ON secretary_runs(status, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS idx_secretary_runs_trigger_created
  ON secretary_runs(trigger_kind, created_at_ms DESC);

CREATE TABLE IF NOT EXISTS secretary_tool_calls (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  status TEXT NOT NULL,
  requires_confirmation INTEGER NOT NULL DEFAULT 0,
  input_json BLOB,
  output_json BLOB,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(run_id) REFERENCES secretary_runs(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_secretary_tool_calls_run_created
  ON secretary_tool_calls(run_id, created_at_ms ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_secretary_tool_calls_tool_status
  ON secretary_tool_calls(tool_name, status, updated_at_ms DESC);

PRAGMA user_version = 51;
"#,
    )?;
    Ok(())
}

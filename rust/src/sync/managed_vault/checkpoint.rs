use anyhow::Result;
use rusqlite::Connection;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(super) struct ManagedVaultCheckpointState {
    pub(super) generation_id: Option<String>,
    pub(super) checkpoint_token: Option<String>,
    pub(super) protocol_version: Option<u32>,
    pub(super) supports_pull_v2: Option<bool>,
    pub(super) supports_pull_bin_v2: Option<bool>,
    pub(super) last_route: Option<String>,
}

fn kv_key(scope_id: &str, suffix: &str) -> String {
    format!("managed_vault.{suffix}:{scope_id}")
}

fn get_string(conn: &Connection, scope_id: &str, suffix: &str) -> Result<Option<String>> {
    super::super::kv_get_string(conn, &kv_key(scope_id, suffix))
}

fn set_string(conn: &Connection, scope_id: &str, suffix: &str, value: &str) -> Result<()> {
    super::super::kv_set_string(conn, &kv_key(scope_id, suffix), value)
}

fn delete_key(conn: &Connection, scope_id: &str, suffix: &str) -> Result<()> {
    let _ = conn.execute(
        r#"DELETE FROM kv WHERE key = ?1"#,
        rusqlite::params![kv_key(scope_id, suffix)],
    )?;
    Ok(())
}

fn parse_bool(value: Option<String>) -> Option<bool> {
    match value?.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

pub(super) fn load_checkpoint_state(
    conn: &Connection,
    scope_id: &str,
) -> Result<ManagedVaultCheckpointState> {
    let protocol_version = get_string(conn, scope_id, "protocol_version")?
        .and_then(|value| value.trim().parse::<u32>().ok());
    Ok(ManagedVaultCheckpointState {
        generation_id: get_string(conn, scope_id, "generation_id")?,
        checkpoint_token: get_string(conn, scope_id, "checkpoint_token")?,
        protocol_version,
        supports_pull_v2: parse_bool(get_string(conn, scope_id, "supports_pull_v2")?),
        supports_pull_bin_v2: parse_bool(get_string(conn, scope_id, "supports_pull_bin_v2")?),
        last_route: get_string(conn, scope_id, "last_route")?,
    })
}

pub(super) fn store_protocol_state(
    conn: &Connection,
    scope_id: &str,
    state: &ManagedVaultCheckpointState,
) -> Result<()> {
    if let Some(generation_id) = &state.generation_id {
        set_string(conn, scope_id, "generation_id", generation_id)?;
    }
    if let Some(checkpoint_token) = &state.checkpoint_token {
        set_string(conn, scope_id, "checkpoint_token", checkpoint_token)?;
    } else {
        delete_key(conn, scope_id, "checkpoint_token")?;
    }
    if let Some(protocol_version) = state.protocol_version {
        set_string(
            conn,
            scope_id,
            "protocol_version",
            &protocol_version.to_string(),
        )?;
    }
    if let Some(value) = state.supports_pull_v2 {
        set_string(
            conn,
            scope_id,
            "supports_pull_v2",
            if value { "1" } else { "0" },
        )?;
    }
    if let Some(value) = state.supports_pull_bin_v2 {
        set_string(
            conn,
            scope_id,
            "supports_pull_bin_v2",
            if value { "1" } else { "0" },
        )?;
    }
    if let Some(last_route) = &state.last_route {
        set_string(conn, scope_id, "last_route", last_route)?;
    }
    Ok(())
}

pub(super) fn mark_pull_v2_supported(
    conn: &Connection,
    scope_id: &str,
    last_route: &str,
) -> Result<()> {
    let mut state = load_checkpoint_state(conn, scope_id)?;
    state.supports_pull_v2 = Some(true);
    state.last_route = Some(last_route.to_string());
    store_protocol_state(conn, scope_id, &state)
}

pub(super) fn mark_pull_v2_unsupported(conn: &Connection, scope_id: &str) -> Result<()> {
    let mut state = load_checkpoint_state(conn, scope_id)?;
    state.supports_pull_v2 = Some(false);
    store_protocol_state(conn, scope_id, &state)
}

pub(super) fn mark_pull_bin_v2_supported(
    conn: &Connection,
    scope_id: &str,
    last_route: &str,
) -> Result<()> {
    let mut state = load_checkpoint_state(conn, scope_id)?;
    state.supports_pull_bin_v2 = Some(true);
    state.last_route = Some(last_route.to_string());
    store_protocol_state(conn, scope_id, &state)
}

pub(super) fn mark_pull_bin_v2_unsupported(conn: &Connection, scope_id: &str) -> Result<()> {
    let mut state = load_checkpoint_state(conn, scope_id)?;
    state.supports_pull_bin_v2 = Some(false);
    store_protocol_state(conn, scope_id, &state)
}

pub(super) fn store_checkpoint_success(
    conn: &Connection,
    scope_id: &str,
    generation_id: &str,
    checkpoint_token: Option<&str>,
    protocol_version: u32,
    last_route: &str,
) -> Result<()> {
    let mut state = load_checkpoint_state(conn, scope_id)?;
    state.generation_id = Some(generation_id.to_string());
    state.checkpoint_token = checkpoint_token.map(str::to_string);
    state.protocol_version = Some(protocol_version);
    state.last_route = Some(last_route.to_string());
    state.supports_pull_v2 = Some(true);
    if last_route == "ops:pull_bin_v2" {
        state.supports_pull_bin_v2 = Some(true);
    }
    store_protocol_state(conn, scope_id, &state)
}

pub(super) fn clear_checkpoint_state(conn: &Connection, scope_id: &str) -> Result<()> {
    delete_key(conn, scope_id, "generation_id")?;
    delete_key(conn, scope_id, "checkpoint_token")?;
    delete_key(conn, scope_id, "protocol_version")?;
    delete_key(conn, scope_id, "last_route")?;
    Ok(())
}

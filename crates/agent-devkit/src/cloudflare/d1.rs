use super::{
    CloudflareHttpMethod, CloudflareRestClient, CloudflareTransport,
    provider_support::validate_cloudflare_segment,
};
use crate::{
    DeploymentTarget, DesiredDeploymentState, DeveloperAuthorization, DevkitError, DevkitErrorCode,
    DevkitResult, RemoteMutationRisk, SensitiveInputResolver,
};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

pub(super) const D1_BINDING_NAME: &str = "ENTITLEMENTS";
const MIGRATION_TABLE: &str = "agentweave_gateway_migrations";
const MAX_BOOTSTRAP_ROWS: usize = 10_000;
const MAX_D1_BATCH_STATEMENTS: usize = 1_000;
const MAX_D1_SQL_BYTES: usize = 512 * 1024;
const MIGRATIONS: [(&str, &str); 3] = [
    (
        "0001_initial.sql",
        include_str!("../../../../gateway/cloudflare-worker/migrations/0001_initial.sql"),
    ),
    (
        "0002_security_boundaries.sql",
        include_str!(
            "../../../../gateway/cloudflare-worker/migrations/0002_security_boundaries.sql"
        ),
    ),
    (
        "0003_signed_entitlement_projections.sql",
        include_str!(
            "../../../../gateway/cloudflare-worker/migrations/0003_signed_entitlement_projections.sql"
        ),
    ),
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct D1Database {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Debug)]
pub(super) struct PreparedD1Resources {
    pub database: D1Database,
    pub migration_hash: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum D1MigrationStatus {
    Missing,
    InSync,
    Drifted,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct EntitlementBootstrap {
    schema_version: u32,
    period_start: i64,
    period_end: i64,
    replace_subjects: bool,
    deployment: DeploymentBudget,
    #[serde(default)]
    tenants: Vec<TenantBudget>,
    #[serde(default)]
    subjects: Vec<SubjectBudget>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DeploymentBudget {
    status: String,
    max_requests: i64,
    max_units: i64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TenantBudget {
    provider_id: String,
    issuer: String,
    tenant: String,
    status: String,
    max_requests: i64,
    max_units: i64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SubjectBudget {
    provider_id: String,
    issuer: String,
    tenant: String,
    subject: String,
    status: String,
    max_requests: i64,
    max_units: i64,
    max_concurrency: i64,
}

pub(super) fn migration_hash() -> String {
    let mut digest = Sha256::new();
    for (name, sql) in MIGRATIONS {
        digest.update((name.len() as u64).to_be_bytes());
        digest.update(name.as_bytes());
        digest.update((sql.len() as u64).to_be_bytes());
        digest.update(sql.as_bytes());
    }
    hex::encode(digest.finalize())
}

pub(super) fn database_name(target: &DeploymentTarget) -> String {
    let suffix = "-entitlements";
    let maximum_prefix = 63_usize.saturating_sub(suffix.len());
    let prefix = if target.resource_name.len() <= maximum_prefix {
        target.resource_name.clone()
    } else {
        let hash = hex::encode(Sha256::digest(target.resource_name.as_bytes()));
        let retained = maximum_prefix.saturating_sub(9);
        format!("{}-{}", &target.resource_name[..retained], &hash[..8])
    };
    format!("{prefix}{suffix}")
}

pub(super) async fn inspect_database<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<Option<D1Database>>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let expected_name = database_name(target);
    let result = rest
        .get_json_with_query(
            Some(authorization),
            &format!("accounts/{}/d1/database", target.account_id),
            &BTreeMap::from([
                ("name".into(), expected_name.clone()),
                ("per_page".into(), "100".into()),
            ]),
        )
        .await?;
    parse_database_list(&result.value, &expected_name)
}

pub(super) async fn inspect_migrations<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    database: &D1Database,
) -> DevkitResult<D1MigrationStatus>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let table = d1_query(
        rest,
        authorization,
        target,
        database,
        "SELECT name FROM sqlite_schema WHERE type = 'table' AND name = ?1",
        vec![json!(MIGRATION_TABLE)],
    )
    .await?;
    let rows = query_rows(&table)?;
    if rows.is_empty() {
        return Ok(D1MigrationStatus::Missing);
    }
    if rows.len() != 1 || rows[0].get("name").and_then(Value::as_str) != Some(MIGRATION_TABLE) {
        return Ok(D1MigrationStatus::Drifted);
    }
    let applied = d1_query(
        rest,
        authorization,
        target,
        database,
        &format!("SELECT name, sha256 FROM {MIGRATION_TABLE}"),
        Vec::new(),
    )
    .await?;
    let applied = parse_applied_migrations(&applied)?;
    Ok(if applied == expected_migration_hashes() {
        D1MigrationStatus::InSync
    } else {
        D1MigrationStatus::Drifted
    })
}

pub(super) async fn ensure_resources<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    desired: &DesiredDeploymentState,
) -> DevkitResult<PreparedD1Resources>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    validate_gateway_public_configuration(desired)?;
    let database = match inspect_database(rest, authorization, desired.target()).await? {
        Some(database) => database,
        None => create_database(rest, authorization, desired.target()).await?,
    };
    apply_migrations(rest, authorization, desired.target(), &database).await?;
    seed_entitlements(rest, authorization, desired, &database).await?;
    Ok(PreparedD1Resources {
        database,
        migration_hash: migration_hash(),
    })
}

pub(super) async fn delete_database<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    expected_database_id: &str,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    validate_cloudflare_segment("D1 database id", expected_database_id)?;
    match inspect_database(rest, authorization, target).await? {
        None => return Ok(()),
        Some(database) if database.id != expected_database_id => {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "Cloudflare D1 database identity changed after the destroy plan was created",
            ));
        }
        Some(_) => {}
    }
    let path = format!(
        "accounts/{}/d1/database/{expected_database_id}",
        target.account_id
    );
    match rest
        .execute_json(
            Some(authorization),
            CloudflareHttpMethod::Delete,
            &path,
            None,
        )
        .await
    {
        Ok(_) => {}
        Err(error) if error.code == DevkitErrorCode::NotFound => return Ok(()),
        Err(error) if error.remote_mutation_risk == RemoteMutationRisk::Possible => {
            if inspect_database(rest, authorization, target)
                .await?
                .is_none()
            {
                return Ok(());
            }
            return Err(error);
        }
        Err(error) => return Err(error),
    }
    if inspect_database(rest, authorization, target)
        .await?
        .is_some()
    {
        return Err(DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "Cloudflare D1 database still exists after deletion",
        ));
    }
    Ok(())
}

pub(super) fn validate_gateway_public_configuration(
    desired: &DesiredDeploymentState,
) -> DevkitResult<()> {
    let gateway = desired
        .public_configuration()
        .get("gateway_config")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("Cloudflare gateway configuration is required")
        })?;
    if gateway.is_empty()
        || serde_json::to_vec(gateway).map_or(true, |bytes| bytes.len() > 256 * 1024)
    {
        return Err(DevkitError::invalid_configuration(
            "Cloudflare gateway configuration is invalid or too large",
        ));
    }
    let bootstrap: EntitlementBootstrap = serde_json::from_value(
        desired
            .public_configuration()
            .get("entitlement_bootstrap")
            .cloned()
            .ok_or_else(|| {
                DevkitError::invalid_configuration("entitlement bootstrap is required")
            })?,
    )
    .map_err(|_| DevkitError::invalid_configuration("entitlement bootstrap is invalid"))?;
    validate_bootstrap(&bootstrap)
}

fn validate_bootstrap(bootstrap: &EntitlementBootstrap) -> DevkitResult<()> {
    if bootstrap.schema_version != 1
        || bootstrap.period_start < 0
        || bootstrap.period_end <= bootstrap.period_start
        || bootstrap.tenants.len() > MAX_BOOTSTRAP_ROWS
        || bootstrap.subjects.len() > MAX_BOOTSTRAP_ROWS
        || !valid_budget_status(&bootstrap.deployment.status, false)
        || bootstrap.deployment.max_requests <= 0
        || bootstrap.deployment.max_units <= 0
    {
        return Err(DevkitError::invalid_configuration(
            "entitlement bootstrap limits are invalid",
        ));
    }
    let mut tenant_keys = BTreeSet::new();
    for tenant in &bootstrap.tenants {
        validate_identity_fields(&tenant.provider_id, &tenant.issuer, &tenant.tenant, None)?;
        if !valid_budget_status(&tenant.status, false)
            || tenant.max_requests <= 0
            || tenant.max_units <= 0
            || !tenant_keys.insert((
                tenant.provider_id.as_str(),
                tenant.issuer.as_str(),
                tenant.tenant.as_str(),
            ))
        {
            return Err(DevkitError::invalid_configuration(
                "tenant entitlement bootstrap is invalid",
            ));
        }
    }
    let mut subject_keys = BTreeSet::new();
    for subject in &bootstrap.subjects {
        validate_identity_fields(
            &subject.provider_id,
            &subject.issuer,
            &subject.tenant,
            Some(&subject.subject),
        )?;
        if !valid_budget_status(&subject.status, true)
            || subject.max_requests <= 0
            || subject.max_units <= 0
            || !(1..=1_000).contains(&subject.max_concurrency)
            || !subject_keys.insert((
                subject.provider_id.as_str(),
                subject.issuer.as_str(),
                subject.tenant.as_str(),
                subject.subject.as_str(),
            ))
        {
            return Err(DevkitError::invalid_configuration(
                "subject entitlement bootstrap is invalid",
            ));
        }
    }
    Ok(())
}

fn validate_identity_fields(
    provider_id: &str,
    issuer: &str,
    tenant: &str,
    subject: Option<&str>,
) -> DevkitResult<()> {
    for value in [Some(provider_id), Some(issuer), Some(tenant), subject]
        .into_iter()
        .flatten()
    {
        if value.is_empty() || value.len() > 512 || value.chars().any(char::is_control) {
            return Err(DevkitError::invalid_configuration(
                "entitlement identity binding is invalid",
            ));
        }
    }
    Ok(())
}

fn valid_budget_status(value: &str, subject: bool) -> bool {
    if subject {
        matches!(value, "active" | "suspended" | "revoked")
    } else {
        matches!(value, "active" | "suspended" | "disabled")
    }
}

async fn create_database<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<D1Database>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let name = database_name(target);
    let result = match rest
        .execute_json(
            Some(authorization),
            CloudflareHttpMethod::Post,
            &format!("accounts/{}/d1/database", target.account_id),
            Some(&json!({"name": name})),
        )
        .await
    {
        Ok(result) => result,
        Err(error) if error.remote_mutation_risk == RemoteMutationRisk::Possible => {
            if let Some(database) = inspect_database(rest, authorization, target).await? {
                return Ok(database);
            }
            return Err(error);
        }
        Err(error) => return Err(error),
    };
    parse_database(&result.value, &name)
}

fn parse_database_list(value: &Value, expected_name: &str) -> DevkitResult<Option<D1Database>> {
    let records = value.as_array().ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 database list has an invalid shape",
        )
    })?;
    let mut matches = Vec::new();
    for record in records {
        let database = parse_database(record, expected_name)?;
        if database.name == expected_name {
            matches.push(database);
        }
    }
    match matches.len() {
        0 => Ok(None),
        1 => Ok(matches.pop()),
        _ => Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare returned duplicate D1 database names",
        )),
    }
}

fn parse_database(value: &Value, expected_name: &str) -> DevkitResult<D1Database> {
    let id = value
        .get("uuid")
        .or_else(|| value.get("id"))
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare D1 database omitted its id",
            )
        })?;
    let name = value.get("name").and_then(Value::as_str).ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 database omitted its name",
        )
    })?;
    validate_cloudflare_segment("D1 database id", id)?;
    validate_cloudflare_segment("D1 database name", name)?;
    if name != expected_name {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 query returned a different database",
        ));
    }
    Ok(D1Database {
        id: id.into(),
        name: name.into(),
    })
}

async fn apply_migrations<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    database: &D1Database,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    d1_query(
        rest,
        authorization,
        target,
        database,
        &format!(
            "CREATE TABLE IF NOT EXISTS {MIGRATION_TABLE} (name TEXT PRIMARY KEY, sha256 TEXT NOT NULL, applied_at INTEGER NOT NULL)"
        ),
        Vec::new(),
    )
    .await?;
    let applied = d1_query(
        rest,
        authorization,
        target,
        database,
        &format!("SELECT name, sha256 FROM {MIGRATION_TABLE}"),
        Vec::new(),
    )
    .await?;
    let applied = parse_applied_migrations(&applied)?;
    for (name, sql) in MIGRATIONS {
        let hash = hex::encode(Sha256::digest(sql.as_bytes()));
        match applied.get(name) {
            Some(existing) if existing == &hash => continue,
            Some(_) => {
                return Err(DevkitError::new(
                    DevkitErrorCode::DriftDetected,
                    "an applied D1 migration differs from the bundled migration",
                ));
            }
            None => {}
        }
        let mut statements = split_sql_statements(sql)?
            .into_iter()
            .map(|sql| (sql, Vec::new()))
            .collect::<Vec<_>>();
        statements.push((
            format!(
                "INSERT INTO {MIGRATION_TABLE} (name, sha256, applied_at) VALUES (?1, ?2, unixepoch())"
            ),
            vec![json!(name), json!(hash)],
        ));
        d1_batch(rest, authorization, target, database, statements).await?;
    }
    Ok(())
}

fn split_sql_statements(sql: &str) -> DevkitResult<Vec<String>> {
    #[derive(Clone, Copy, Eq, PartialEq)]
    enum State {
        Normal,
        SingleQuoted,
        DoubleQuoted,
        BracketQuoted,
        LineComment,
        BlockComment,
    }

    let mut state = State::Normal;
    let mut chars = sql.chars().peekable();
    let mut current = String::new();
    let mut statements = Vec::new();
    while let Some(character) = chars.next() {
        match state {
            State::Normal => match character {
                '\'' => {
                    current.push(character);
                    state = State::SingleQuoted;
                }
                '"' => {
                    current.push(character);
                    state = State::DoubleQuoted;
                }
                '[' => {
                    current.push(character);
                    state = State::BracketQuoted;
                }
                '-' if chars.peek() == Some(&'-') => {
                    current.push(character);
                    current.push(chars.next().expect("peeked SQL comment delimiter"));
                    state = State::LineComment;
                }
                '/' if chars.peek() == Some(&'*') => {
                    current.push(character);
                    current.push(chars.next().expect("peeked SQL comment delimiter"));
                    state = State::BlockComment;
                }
                ';' => {
                    let statement = current.trim();
                    if !statement.is_empty() {
                        statements.push(statement.to_owned());
                    }
                    current.clear();
                }
                _ => current.push(character),
            },
            State::SingleQuoted => {
                current.push(character);
                if character == '\'' {
                    if chars.peek() == Some(&'\'') {
                        current.push(chars.next().expect("peeked escaped SQL quote"));
                    } else {
                        state = State::Normal;
                    }
                }
            }
            State::DoubleQuoted => {
                current.push(character);
                if character == '"' {
                    if chars.peek() == Some(&'"') {
                        current.push(chars.next().expect("peeked escaped SQL quote"));
                    } else {
                        state = State::Normal;
                    }
                }
            }
            State::BracketQuoted => {
                current.push(character);
                if character == ']' {
                    if chars.peek() == Some(&']') {
                        current.push(chars.next().expect("peeked escaped SQL bracket"));
                    } else {
                        state = State::Normal;
                    }
                }
            }
            State::LineComment => {
                current.push(character);
                if character == '\n' {
                    state = State::Normal;
                }
            }
            State::BlockComment => {
                current.push(character);
                if character == '*' && chars.peek() == Some(&'/') {
                    current.push(chars.next().expect("peeked SQL comment terminator"));
                    state = State::Normal;
                }
            }
        }
    }
    if matches!(
        state,
        State::SingleQuoted | State::DoubleQuoted | State::BracketQuoted | State::BlockComment
    ) {
        return Err(DevkitError::invalid_configuration(
            "D1 migration contains an unterminated SQL literal or comment",
        ));
    }
    let tail = current.trim();
    if !tail.is_empty() {
        statements.push(tail.to_owned());
    }
    if statements.is_empty()
        || statements.len() > MAX_D1_BATCH_STATEMENTS
        || statements.iter().map(String::len).sum::<usize>() > MAX_D1_SQL_BYTES
    {
        return Err(DevkitError::invalid_configuration(
            "D1 migration batch exceeds its safety limits",
        ));
    }
    Ok(statements)
}

async fn d1_batch<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    database: &D1Database,
    statements: Vec<(String, Vec<Value>)>,
) -> DevkitResult<Value>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    if statements.is_empty()
        || statements.len() > MAX_D1_BATCH_STATEMENTS
        || statements.iter().any(|(sql, _)| sql.is_empty())
        || statements.iter().map(|(sql, _)| sql.len()).sum::<usize>() > MAX_D1_SQL_BYTES
    {
        return Err(DevkitError::invalid_configuration(
            "D1 query batch is invalid or too large",
        ));
    }
    let batch = statements
        .into_iter()
        .map(|(sql, params)| json!({"sql": sql, "params": params}))
        .collect::<Vec<_>>();
    let value = rest
        .execute_json(
            Some(authorization),
            CloudflareHttpMethod::Post,
            &format!(
                "accounts/{}/d1/database/{}/query",
                target.account_id, database.id
            ),
            Some(&json!({"batch": batch})),
        )
        .await?
        .value;
    validate_d1_query_result(&value)?;
    Ok(value)
}

fn parse_applied_migrations(value: &Value) -> DevkitResult<BTreeMap<String, String>> {
    let rows = query_rows(value)?;
    let mut applied = BTreeMap::new();
    for row in rows {
        let name = row.get("name").and_then(Value::as_str).ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare D1 migration row is invalid",
            )
        })?;
        let hash = row.get("sha256").and_then(Value::as_str).ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare D1 migration row is invalid",
            )
        })?;
        if applied.insert(name.into(), hash.into()).is_some() {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare D1 migration rows contain duplicates",
            ));
        }
    }
    Ok(applied)
}

fn query_rows(value: &Value) -> DevkitResult<&[Value]> {
    let results = value.as_array().ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 query omitted its result set",
        )
    })?;
    if results.len() != 1 {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 single query returned an ambiguous result set",
        ));
    }
    results[0]
        .get("results")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare D1 query omitted its rows",
            )
        })
}

pub(super) fn expected_migration_hashes() -> BTreeMap<String, String> {
    MIGRATIONS
        .iter()
        .map(|(name, sql)| {
            (
                (*name).to_owned(),
                hex::encode(Sha256::digest(sql.as_bytes())),
            )
        })
        .collect()
}

async fn seed_entitlements<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    desired: &DesiredDeploymentState,
    database: &D1Database,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let bootstrap: EntitlementBootstrap =
        serde_json::from_value(desired.public_configuration()["entitlement_bootstrap"].clone())
            .map_err(|_| DevkitError::invalid_configuration("entitlement bootstrap is invalid"))?;
    validate_bootstrap(&bootstrap)?;
    let target = desired.target();
    d1_query(
        rest,
        authorization,
        target,
        database,
        "INSERT INTO gateway_deployment_budgets (deployment_id, status, period_start, period_end, max_requests, max_units, used_requests, used_units, reserved_requests, reserved_units, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, 0, 0, 0, unixepoch()) ON CONFLICT (deployment_id, period_start) DO UPDATE SET status = excluded.status, period_end = excluded.period_end, max_requests = excluded.max_requests, max_units = excluded.max_units, updated_at = unixepoch()",
        vec![
            json!(target.deployment_id),
            json!(bootstrap.deployment.status),
            json!(bootstrap.period_start),
            json!(bootstrap.period_end),
            json!(bootstrap.deployment.max_requests),
            json!(bootstrap.deployment.max_units),
        ],
    )
    .await?;
    for tenant in &bootstrap.tenants {
        d1_query(
            rest,
            authorization,
            target,
            database,
            "INSERT INTO gateway_tenant_budgets (deployment_id, provider_id, issuer, tenant, status, period_start, period_end, max_requests, max_units, used_requests, used_units, reserved_requests, reserved_units, policy_source, policy_revision, policy_projection_id, policy_issued_at, policy_expires_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, 0, 0, 0, 'static', 'static-v1', 'static-bootstrap', 0, ?7, unixepoch()) ON CONFLICT (deployment_id, provider_id, issuer, tenant, period_start) DO UPDATE SET status = excluded.status, period_end = excluded.period_end, max_requests = excluded.max_requests, max_units = excluded.max_units, policy_source = excluded.policy_source, policy_revision = excluded.policy_revision, policy_projection_id = excluded.policy_projection_id, policy_issued_at = excluded.policy_issued_at, policy_expires_at = excluded.policy_expires_at, updated_at = unixepoch()",
            vec![
                json!(target.deployment_id),
                json!(tenant.provider_id),
                json!(tenant.issuer),
                json!(tenant.tenant),
                json!(tenant.status),
                json!(bootstrap.period_start),
                json!(bootstrap.period_end),
                json!(tenant.max_requests),
                json!(tenant.max_units),
            ],
        )
        .await?;
    }
    if bootstrap.replace_subjects {
        d1_query(
            rest,
            authorization,
            target,
            database,
            "UPDATE gateway_entitlements SET status = 'revoked', updated_at = unixepoch() WHERE deployment_id = ?1",
            vec![json!(target.deployment_id)],
        )
        .await?;
    }
    for subject in &bootstrap.subjects {
        d1_query(
            rest,
            authorization,
            target,
            database,
            "INSERT INTO gateway_entitlements (deployment_id, provider_id, issuer, tenant, subject, status, period_start, period_end, max_requests, max_units, max_concurrency, used_requests, used_units, reserved_requests, reserved_units, policy_source, policy_revision, policy_projection_id, policy_issued_at, policy_expires_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 0, 0, 0, 0, 'static', 'static-v1', 'static-bootstrap', 0, ?8, unixepoch()) ON CONFLICT (deployment_id, provider_id, issuer, tenant, subject, period_start) DO UPDATE SET status = excluded.status, period_end = excluded.period_end, max_requests = excluded.max_requests, max_units = excluded.max_units, max_concurrency = excluded.max_concurrency, policy_source = excluded.policy_source, policy_revision = excluded.policy_revision, policy_projection_id = excluded.policy_projection_id, policy_issued_at = excluded.policy_issued_at, policy_expires_at = excluded.policy_expires_at, updated_at = unixepoch()",
            vec![
                json!(target.deployment_id),
                json!(subject.provider_id),
                json!(subject.issuer),
                json!(subject.tenant),
                json!(subject.subject),
                json!(subject.status),
                json!(bootstrap.period_start),
                json!(bootstrap.period_end),
                json!(subject.max_requests),
                json!(subject.max_units),
                json!(subject.max_concurrency),
            ],
        )
        .await?;
    }
    Ok(())
}

async fn d1_query<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    database: &D1Database,
    sql: &str,
    params: Vec<Value>,
) -> DevkitResult<Value>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    if sql.is_empty() || sql.len() > MAX_D1_SQL_BYTES {
        return Err(DevkitError::invalid_configuration(
            "D1 migration or bootstrap SQL is invalid",
        ));
    }
    let value = rest
        .execute_json(
            Some(authorization),
            CloudflareHttpMethod::Post,
            &format!(
                "accounts/{}/d1/database/{}/query",
                target.account_id, database.id
            ),
            Some(&json!({"sql": sql, "params": params})),
        )
        .await?
        .value;
    validate_d1_query_result(&value)?;
    Ok(value)
}

fn validate_d1_query_result(value: &Value) -> DevkitResult<()> {
    let results = value.as_array().ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 query returned an invalid result shape",
        )
    })?;
    if results.is_empty()
        || results.iter().any(|result| {
            result.get("success").and_then(Value::as_bool) != Some(true)
                || !result
                    .get("results")
                    .is_some_and(|rows| rows.is_array() || rows.is_null())
        })
    {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare D1 rejected a query without applying a verified result",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_migrations_split_into_bounded_query_batches() {
        for (_, sql) in MIGRATIONS {
            let statements = split_sql_statements(sql).unwrap();
            assert!(!statements.is_empty());
            assert!(statements.len() < MAX_D1_BATCH_STATEMENTS);
            assert!(statements.iter().all(|statement| !statement.ends_with(';')));
        }
    }

    #[test]
    fn splitter_preserves_quoted_semicolons_and_comments() {
        let statements = split_sql_statements(
            "-- first; comment\nINSERT INTO example VALUES ('a;''b'); /* ; */ SELECT \"c;d\";",
        )
        .unwrap();
        assert_eq!(statements.len(), 2);
        assert!(statements[0].contains("'a;''b'"));
        assert!(statements[1].contains("\"c;d\""));
    }

    #[test]
    fn splitter_rejects_unterminated_literals_and_comments() {
        for sql in ["SELECT 'unterminated", "SELECT 1 /* unterminated"] {
            assert!(split_sql_statements(sql).is_err());
        }
    }

    #[test]
    fn d1_batch_items_must_each_report_success() {
        assert!(
            validate_d1_query_result(&json!([{
                "success": true,
                "results": []
            }]))
            .is_ok()
        );
        for invalid in [
            json!([]),
            json!([{"success": false, "results": []}]),
            json!([{"success": true}]),
        ] {
            assert!(validate_d1_query_result(&invalid).is_err());
        }
    }
}

use super::d1::{
    D1Database, D1MigrationStatus, PreparedD1Resources, d1_batch, d1_query,
    parse_applied_migrations, parse_database, parse_database_list, query_rows,
    split_sql_statements,
};
use super::provider_support::validate_cloudflare_segment;
use super::{
    CloudflareHttpMethod, CloudflareRestClient, CloudflareTransport, RequestBodySensitivity,
};
use crate::{
    DeploymentTarget, DesiredDeploymentState, DeveloperAuthorization, DevkitError, DevkitErrorCode,
    DevkitResult, RemoteMutationRisk, SensitiveInputResolver,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

pub(super) const COMMERCE_D1_BINDING_NAME: &str = "COMMERCE";
const CREEM_PROVIDER_ID: &str = "agentweave.commerce.creem";
const MIGRATION_TABLE: &str = "agentweave_commerce_migrations";
const MIGRATIONS: [(&str, &str); 2] = [
    (
        "0001_commerce.sql",
        include_str!("../../../../entitlements/cloudflare-worker/migrations/0001_commerce.sql"),
    ),
    (
        "0002_portal_verification_nonce.sql",
        include_str!(
            "../../../../entitlements/cloudflare-worker/migrations/0002_portal_verification_nonce.sql"
        ),
    ),
];

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
    let suffix = "-commerce";
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

pub(super) fn validate_entitlement_public_configuration(
    desired: &DesiredDeploymentState,
) -> DevkitResult<bool> {
    if desired
        .public_configuration()
        .get("worker_role")
        .and_then(Value::as_str)
        != Some("entitlement_policy")
    {
        return Err(DevkitError::invalid_configuration(
            "Cloudflare entitlement Worker role is invalid",
        ));
    }
    let config = desired
        .public_configuration()
        .get("entitlement_config")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("Cloudflare entitlement configuration is required")
        })?;
    if config.is_empty()
        || serde_json::to_vec(config).map_or(true, |bytes| bytes.len() > 256 * 1024)
    {
        return Err(DevkitError::invalid_configuration(
            "Cloudflare entitlement configuration is invalid or too large",
        ));
    }
    if let Some(setup) = config.get("setup") {
        let valid = setup.as_object().is_some_and(|setup| {
            setup.len() == 3
                && setup.get("mode").and_then(Value::as_str) == Some("commerce_webhook")
                && setup.get("providerId").and_then(Value::as_str) == Some(CREEM_PROVIDER_ID)
                && setup
                    .get("environment")
                    .and_then(Value::as_str)
                    .is_some_and(|value| matches!(value, "test" | "production"))
        }) && config.len() == 6
            && config.get("schemaVersion").and_then(Value::as_u64) == Some(1)
            && ["environment", "appId", "deploymentId", "configurationId"]
                .into_iter()
                .all(|name| {
                    config
                        .get(name)
                        .and_then(Value::as_str)
                        .is_some_and(|value| !value.is_empty())
                });
        return if valid {
            Ok(false)
        } else {
            Err(DevkitError::invalid_configuration(
                "Cloudflare Commerce webhook setup configuration is invalid",
            ))
        };
    }
    let source_mode = config
        .get("policy")
        .and_then(Value::as_object)
        .and_then(|policy| policy.get("sourceMode"))
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("Cloudflare entitlement policy source is required")
        })?;
    match source_mode {
        "uniform_bounded" => Ok(false),
        "commerce_provider" => Ok(true),
        _ => Err(DevkitError::invalid_configuration(
            "Cloudflare entitlement policy source is unsupported",
        )),
    }
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
    Ok(
        if parse_applied_migrations(&applied)? == expected_migration_hashes() {
            D1MigrationStatus::InSync
        } else {
            D1MigrationStatus::Drifted
        },
    )
}

pub(super) async fn inspect_verifications<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    database: &D1Database,
) -> DevkitResult<BTreeMap<String, i64>>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let result = d1_query(
        rest,
        authorization,
        target,
        database,
        "SELECT capability, verified_at FROM commerce_verifications WHERE app_id IS NOT NULL ORDER BY capability",
        Vec::new(),
    )
    .await?;
    let mut verifications = BTreeMap::new();
    for row in query_rows(&result)? {
        let capability = row
            .get("capability")
            .and_then(Value::as_str)
            .filter(|value| matches!(*value, "signed_webhook_v1" | "customer_portal_v1"))
            .ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::RemoteProtocol,
                    "Commerce verification row is invalid",
                )
            })?;
        let verified_at = row
            .get("verified_at")
            .and_then(Value::as_i64)
            .filter(|value| *value > 0)
            .ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::RemoteProtocol,
                    "Commerce verification row is invalid",
                )
            })?;
        if verifications
            .insert(capability.to_owned(), verified_at)
            .is_some()
        {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Commerce verification rows contain duplicates",
            ));
        }
    }
    Ok(verifications)
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
    if !validate_entitlement_public_configuration(desired)? {
        return Err(DevkitError::invalid_configuration(
            "uniform entitlement policy does not use a Commerce D1 database",
        ));
    }
    let database = match inspect_database(rest, authorization, desired.target()).await? {
        Some(database) => database,
        None => create_database(rest, authorization, desired.target()).await?,
    };
    apply_migrations(rest, authorization, desired.target(), &database).await?;
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
                "Cloudflare Commerce D1 identity changed after the destroy plan was created",
            ));
        }
        Some(_) => {}
    }
    let path = format!(
        "accounts/{}/d1/database/{expected_database_id}",
        target.account_id
    );
    match rest
        .execute_bytes(
            Some(authorization),
            CloudflareHttpMethod::Delete,
            &path,
            Vec::new(),
            RequestBodySensitivity::Public,
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
            "Cloudflare Commerce D1 still exists after deletion",
        ));
    }
    Ok(())
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
                    "an applied Commerce D1 migration differs from the bundled migration",
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

fn expected_migration_hashes() -> BTreeMap<String, String> {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commerce_database_name_and_migration_are_deterministic() {
        let target = DeploymentTarget {
            provider_id: "cloudflare-workers".into(),
            account_id: "account".into(),
            app_id: "com.example.agent".into(),
            deployment_id: "production".into(),
            resource_name: "example-gateway-entitlements".into(),
        };
        assert_eq!(
            database_name(&target),
            "example-gateway-entitlements-commerce"
        );
        assert_eq!(migration_hash().len(), 64);
        assert!(!split_sql_statements(MIGRATIONS[0].1).unwrap().is_empty());
    }
}

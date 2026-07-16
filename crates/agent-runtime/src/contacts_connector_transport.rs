use crate::connector::{
    ConnectorApprovalMode, ConnectorDescriptor, ConnectorHealth, ConnectorToolRisk,
    ConnectorToolSpec, ConnectorTransport, ConnectorTransportCall, ConnectorTransportKind,
};
use crate::contacts::{ApprovedContactMutation, ContactRecord, ContactScope, ContactsConnector};
use crate::credential::CredentialScope;
use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::sync::Arc;

pub const CONTACTS_CONNECTOR_ID: &str = "agentweave-contacts";
pub const CONTACTS_TOOL_NAMES: [&str; 4] = [
    "contacts_resolve",
    "contact_get",
    "contact_update_preview",
    "contact_update_apply",
];

pub struct ContactsConnectorTransport {
    connector: Arc<dyn ContactsConnector>,
    scope: CredentialScope,
}

impl ContactsConnectorTransport {
    pub fn new(
        connector: Arc<dyn ContactsConnector>,
        scope: CredentialScope,
    ) -> anyhow::Result<Self> {
        scope.validate()?;
        Ok(Self { connector, scope })
    }

    pub fn descriptor(name: impl Into<String>, required_startup: bool) -> ConnectorDescriptor {
        ConnectorDescriptor {
            id: CONTACTS_CONNECTOR_ID.into(),
            name: name.into(),
            version: "0.1.0".into(),
            instructions: Some(
                "Provider-neutral Contacts v1. Resolve ambiguous identities explicitly; synchronized updates require an approved immutable preview."
                    .into(),
            ),
            transport: ConnectorTransportKind::LocalHost,
            required_startup,
            account_required: false,
            approval_mode: ConnectorApprovalMode::Writes,
            allowed_tools: BTreeSet::new(),
            denied_tools: BTreeSet::new(),
        }
    }

    fn contact_scope(
        &self,
        account_id: String,
        trusted_account_id: Option<&str>,
    ) -> anyhow::Result<ContactScope> {
        validate_text(&account_id, 255, "Contacts account id")?;
        if let Some(trusted) = trusted_account_id {
            anyhow::ensure!(
                trusted == account_id,
                "Contacts account does not match the trusted connector account"
            );
        }
        Ok(ContactScope {
            app_id: self.scope.app_id.clone(),
            tenant_id: self.scope.tenant_id.clone(),
            user_id: self.scope.user_id.clone(),
            account_id,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ResolveRequest {
    account_id: String,
    query: String,
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GetRequest {
    account_id: String,
    contact_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdatePreviewRequest {
    account_id: String,
    contact_id: String,
    expected_version: u64,
    replacement: ContactRecord,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ApplyRequest {
    account_id: String,
    approval: ApprovedContactMutation,
}

#[async_trait]
impl ConnectorTransport for ContactsConnectorTransport {
    async fn start(&self) -> anyhow::Result<()> {
        Ok(())
    }

    async fn list_tools(&self) -> anyhow::Result<Vec<ConnectorToolSpec>> {
        Ok(contacts_tool_specs())
    }

    async fn call(&self, request: ConnectorTransportCall) -> anyhow::Result<Value> {
        let trusted_account = request.account_id.as_deref();
        match request.tool_name.as_str() {
            "contacts_resolve" => {
                let input: ResolveRequest = serde_json::from_value(request.arguments)?;
                let scope = self.contact_scope(input.account_id, trusted_account)?;
                serde_json::to_value(
                    self.connector
                        .resolve(&scope, &input.query, input.limit)
                        .await?,
                )
                .map_err(Into::into)
            }
            "contact_get" => {
                let input: GetRequest = serde_json::from_value(request.arguments)?;
                let scope = self.contact_scope(input.account_id, trusted_account)?;
                serde_json::to_value(self.connector.get(&scope, &input.contact_id).await?)
                    .map_err(Into::into)
            }
            "contact_update_preview" => {
                let input: UpdatePreviewRequest = serde_json::from_value(request.arguments)?;
                let scope = self.contact_scope(input.account_id, trusted_account)?;
                serde_json::to_value(
                    self.connector
                        .preview_update(
                            &scope,
                            &input.contact_id,
                            input.expected_version,
                            input.replacement,
                            input.idempotency_key,
                        )
                        .await?,
                )
                .map_err(Into::into)
            }
            "contact_update_apply" => {
                let input: ApplyRequest = serde_json::from_value(request.arguments)?;
                let scope = self.contact_scope(input.account_id, trusted_account)?;
                anyhow::ensure!(
                    request.idempotency_key.is_some(),
                    "contact update requires a trusted idempotency key"
                );
                serde_json::to_value(self.connector.apply(&scope, input.approval).await?)
                    .map_err(Into::into)
            }
            _ => anyhow::bail!("unknown Contacts connector tool"),
        }
    }

    async fn health(&self) -> anyhow::Result<ConnectorHealth> {
        Ok(ConnectorHealth::Ready)
    }

    async fn stop(&self) -> anyhow::Result<()> {
        Ok(())
    }
}

fn contacts_tool_specs() -> Vec<ConnectorToolSpec> {
    vec![
        spec(
            "contacts_resolve",
            "Resolve a bounded set of authoritative contact candidates without choosing among ambiguous matches.",
            schema(&["accountId", "query", "limit"]),
            ConnectorToolRisk::SensitiveRead,
            &["contacts.read"],
            true,
            false,
        ),
        spec(
            "contact_get",
            "Inspect one authoritative provider contact by stable ID.",
            schema(&["accountId", "contactId"]),
            ConnectorToolRisk::SensitiveRead,
            &["contacts.read"],
            true,
            false,
        ),
        spec(
            "contact_update_preview",
            "Preview an exact version-checked contact update without mutating the provider address book.",
            schema(&[
                "accountId",
                "contactId",
                "expectedVersion",
                "replacement",
                "idempotencyKey",
            ]),
            ConnectorToolRisk::SensitiveRead,
            &["contacts.write"],
            false,
            false,
        ),
        spec(
            "contact_update_apply",
            "Apply exactly one Runtime-approved immutable Contacts preview.",
            schema(&["accountId", "approval"]),
            ConnectorToolRisk::Write,
            &["contacts.write"],
            false,
            true,
        ),
    ]
}

fn spec(
    name: &str,
    description: &str,
    input_schema: Value,
    risk: ConnectorToolRisk,
    scopes: &[&str],
    parallel_safe: bool,
    supports_idempotency: bool,
) -> ConnectorToolSpec {
    ConnectorToolSpec {
        name: name.into(),
        description: description.into(),
        input_schema,
        output_schema: None,
        risk,
        required_scopes: scopes.iter().map(|scope| (*scope).into()).collect(),
        parallel_safe,
        supports_idempotency,
    }
}

fn schema(required: &[&str]) -> Value {
    let properties = required
        .iter()
        .map(|name| ((*name).to_string(), property_schema(name)))
        .collect::<serde_json::Map<_, _>>();
    json!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false
    })
}

fn property_schema(name: &str) -> Value {
    match name {
        "replacement" | "approval" => json!({"type": "object"}),
        "expectedVersion" | "limit" => json!({"type": "integer", "minimum": 1}),
        _ => json!({"type": "string", "minLength": 1}),
    }
}

fn validate_text(value: &str, max: usize, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.trim().is_empty(), "{name} is required");
    anyhow::ensure!(value.len() <= max, "{name} is too long");
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{name} contains control characters"
    );
    Ok(())
}

#[cfg(test)]
#[path = "contacts_connector_transport_tests.rs"]
mod tests;

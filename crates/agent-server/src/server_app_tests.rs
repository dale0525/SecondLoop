use super::*;
use agent_runtime::app_definition::AgentAppRuntimePolicy;
use agent_runtime::app_manifest::AgentAppManifest;
use std::collections::HashMap;
use std::ffi::OsString;

fn connector_mode(values: &[(&str, &str)]) -> anyhow::Result<MailConnectorMode> {
    let values = values
        .iter()
        .map(|(name, value)| ((*name).to_string(), OsString::from(value)))
        .collect::<HashMap<_, _>>();
    mail_connector_mode_from_lookup(|name| values.get(name).cloned())
}

fn runtime_config_with_policy(
    network: &str,
    background: &str,
    connectors: &[&str],
) -> RuntimeConfig {
    let manifest = serde_json::json!({
        "schemaVersion": 1,
        "appId": "com.example.policy-test",
        "package": {"id": "com.example.policy-test.app", "version": "0.1.0"},
        "requires": {
            "packages": [],
            "capabilities": [],
            "runtimeTools": [],
            "connectors": connectors
        },
        "features": [],
        "policy": {
            "externalSideEffects": "require_approval",
            "network": network,
            "backgroundExecution": background,
            "memoryPersistence": "disabled",
            "skillManagement": "disabled"
        },
        "branding": {"displayName": "Policy Test"},
        "instructions": {"system": "prompts/system.md"}
    });
    let manifest = AgentAppManifest::parse_json(&serde_json::to_vec(&manifest).unwrap()).unwrap();
    RuntimeConfig::workspace_write(".", ".")
        .with_agent_app_policy(AgentAppRuntimePolicy::compile(&manifest))
}

#[test]
fn mail_connector_defaults_to_an_unconfigured_account_set() {
    assert_eq!(
        connector_mode(&[]).unwrap(),
        MailConnectorMode::Unconfigured
    );
}

#[test]
fn fake_mail_requires_an_explicit_test_flag() {
    assert_eq!(
        connector_mode(&[("AGENTWEAVE_FAKE_MAIL", "enabled")]).unwrap(),
        MailConnectorMode::Fake
    );
}

#[test]
fn imap_smtp_is_selected_explicitly_and_unknown_connectors_fail_closed() {
    assert_eq!(
        connector_mode(&[("AGENTWEAVE_MAIL_CONNECTOR", "imap-smtp")]).unwrap(),
        MailConnectorMode::ImapSmtp
    );
    assert!(connector_mode(&[("AGENTWEAVE_MAIL_CONNECTOR", "unknown")]).is_err());
}

#[test]
fn manifest_background_policy_cannot_be_bypassed_by_host_flags() {
    let disabled = runtime_config_with_policy("deny", "disabled", &[]);
    assert!(!background_execution_allowed(&disabled, true, true));

    let declared = runtime_config_with_policy("deny", "declared_only", &[]);
    assert!(!background_execution_allowed(&declared, false, true));
    assert!(background_execution_allowed(&declared, true, false));

    let enabled = runtime_config_with_policy("deny", "enabled", &[]);
    assert!(background_execution_allowed(&enabled, false, true));
}

#[test]
fn manifest_network_policy_cannot_be_bypassed_by_fake_mail_flag() {
    let denied = runtime_config_with_policy("deny", "disabled", &[MAIL_CONNECTOR_ID]);
    assert!(!mail_foundation_allowed(&denied, true, true));

    let undeclared = runtime_config_with_policy("declared_only", "disabled", &[]);
    assert!(!mail_foundation_allowed(&undeclared, true, true));

    let declared = runtime_config_with_policy("declared_only", "disabled", &[MAIL_CONNECTOR_ID]);
    assert!(mail_foundation_allowed(&declared, true, false));
    assert!(!mail_foundation_allowed(&declared, false, true));
}

#[test]
fn manifest_network_policy_cannot_be_bypassed_by_fake_calendar_flag() {
    let denied = runtime_config_with_policy("deny", "disabled", &[CALENDAR_CONNECTOR_ID]);
    assert!(!calendar_foundation_allowed(&denied, true, true));

    let undeclared = runtime_config_with_policy("declared_only", "disabled", &[]);
    assert!(!calendar_foundation_allowed(&undeclared, true, true));

    let declared =
        runtime_config_with_policy("declared_only", "disabled", &[CALENDAR_CONNECTOR_ID]);
    assert!(calendar_foundation_allowed(&declared, true, false));
    assert!(!calendar_foundation_allowed(&declared, false, true));
}

#[test]
fn manifest_network_policy_cannot_be_bypassed_by_fake_contacts_flag() {
    let denied = runtime_config_with_policy("deny", "disabled", &[CONTACTS_CONNECTOR_ID]);
    assert!(!contacts_foundation_allowed(&denied, true, true));

    let undeclared = runtime_config_with_policy("declared_only", "disabled", &[]);
    assert!(!contacts_foundation_allowed(&undeclared, true, true));

    let declared =
        runtime_config_with_policy("declared_only", "disabled", &[CONTACTS_CONNECTOR_ID]);
    assert!(contacts_foundation_allowed(&declared, true, false));
    assert!(!contacts_foundation_allowed(&declared, false, true));
}

#[tokio::test]
async fn trusted_vault_key_persists_connector_credentials_without_plaintext() {
    let temporary = tempfile::tempdir().unwrap();
    let root = temporary.path().join("credentials");
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = CredentialScope {
        app_id: "com.example.secretary".into(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let secret_id = SecretId::parse("mail.primary.password").unwrap();
    let marker = "trusted-vault-credential-marker";
    let key = SecretMaterial::new(vec![7; 32]).unwrap();
    let first = resolve_credential_vault(&storage, Some(&key), Some(&root))
        .await
        .unwrap()
        .unwrap();
    first
        .save_provider_credential(
            &scope,
            ProviderCredential {
                credential_id: "manual-primary".into(),
                provider_id: "imap-smtp".into(),
                provider_subject: "primary".into(),
                access_secret_id: secret_id,
                refresh_secret_id: None,
                granted_scopes: BTreeSet::from(["mail.message.read".into()]),
                expires_at: None,
                revoked_at: None,
            },
            SecretMaterial::new(marker).unwrap(),
            None,
        )
        .await
        .unwrap();
    first
        .register_account_persistent(ConnectorAccount {
            account_id: "primary".into(),
            connector_id: "agentweave.connector.mail.imap-smtp".into(),
            credential_id: "manual-primary".into(),
            scope: scope.clone(),
            allowed_scopes: BTreeSet::from(["mail.message.read".into()]),
        })
        .await
        .unwrap();
    drop(first);

    for entry in std::fs::read_dir(&root).unwrap() {
        let path = entry.unwrap().path();
        if path.is_file() {
            let bytes = std::fs::read(path).unwrap();
            assert!(
                !bytes
                    .windows(marker.len())
                    .any(|value| value == marker.as_bytes())
            );
        }
    }
    let resumed = resolve_credential_vault(&storage, Some(&key), Some(&root))
        .await
        .unwrap()
        .unwrap();
    assert!(
        resumed
            .connector_credential_configured(
                &scope,
                "agentweave.connector.mail.imap-smtp",
                "primary",
            )
            .await
            .unwrap()
    );
}

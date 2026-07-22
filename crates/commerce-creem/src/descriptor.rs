use crate::CREEM_PROVIDER_ID;
use agent_devkit::{
    ConfigFieldDescriptor, ConfigFieldType, HostPlatform, ProtocolCompatibility,
    ProviderConfigurationSchema, ProviderDescriptor, ProviderKind, SensitiveFieldDescriptor,
};
use commerce_runtime::REQUIRED_SUBSCRIPTION_CAPABILITIES;
use semver::{Version, VersionReq};
use serde_json::json;
use std::collections::BTreeSet;
use url::Url;

pub fn creem_provider_descriptor() -> ProviderDescriptor {
    ProviderDescriptor {
        schema_version: 1,
        package_id: "agentweave-commerce-creem".into(),
        provider_id: CREEM_PROVIDER_ID.into(),
        provider_version: Version::parse(env!("CARGO_PKG_VERSION"))
            .expect("crate version must be semver"),
        protocol_compatibility: ProtocolCompatibility {
            requirement: VersionReq::parse(">=0.1.0, <0.2.0")
                .expect("commerce protocol requirement must be valid"),
        },
        kind: ProviderKind::Commerce,
        display_name: "Creem".into(),
        description: "Discovers subscription products and projects verified Creem billing facts."
            .into(),
        documentation_url: Url::parse("https://docs.creem.io/api-reference/introduction")
            .expect("Creem documentation URL must be valid"),
        risk_notice: "Checkout and customer portal creation are external side effects. Webhook failures deny new model usage when no paid period remains."
            .into(),
        platforms: BTreeSet::from([
            HostPlatform::Macos,
            HostPlatform::Windows,
            HostPlatform::Linux,
            HostPlatform::Server,
        ]),
        capabilities: REQUIRED_SUBSCRIPTION_CAPABILITIES
            .into_iter()
            .map(str::to_owned)
            .collect(),
        configuration_schema: ProviderConfigurationSchema {
            schema_version: 1,
            migration_version: 1,
            public_fields: vec![
                ConfigFieldDescriptor {
                    id: "environment".into(),
                    label: "Creem environment".into(),
                    description: "Test and Production credentials and data never fall back to each other."
                        .into(),
                    field_type: ConfigFieldType::String,
                    required: true,
                    default_value: Some(json!("test")),
                    allowed_values: vec![json!("test"), json!("production")],
                    minimum_length: None,
                    maximum_length: None,
                    advanced: false,
                    visible_when: None,
                },
                ConfigFieldDescriptor {
                    id: "successUrl".into(),
                    label: "Checkout success URL".into(),
                    description: "Server-controlled HTTPS destination used after Checkout."
                        .into(),
                    field_type: ConfigFieldType::HttpsUrl,
                    required: true,
                    default_value: None,
                    allowed_values: Vec::new(),
                    minimum_length: Some(8),
                    maximum_length: Some(2_048),
                    advanced: false,
                    visible_when: None,
                },
            ],
            sensitive_fields: vec![
                secret_field("apiKey", "Creem API key", "commerce_api_authorization", true),
                secret_field(
                    "webhookSecret",
                    "Creem webhook secret",
                    "commerce_webhook_verification",
                    true,
                ),
                secret_field(
                    "subjectBindingSecret",
                    "Subject binding secret",
                    "commerce_subject_binding",
                    true,
                ),
            ],
            cross_field_rules: Vec::new(),
        },
        developer_authorization_schema: None,
    }
}

fn secret_field(
    id: &str,
    label: &str,
    purpose: &str,
    rotation_supported: bool,
) -> SensitiveFieldDescriptor {
    SensitiveFieldDescriptor {
        id: id.into(),
        label: label.into(),
        description: "Stored only in the Host vault and managed Worker secret binding.".into(),
        required: true,
        purpose: purpose.into(),
        rotation_supported,
        visible_when: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use commerce_runtime::CUSTOMER_PORTAL_CAPABILITY;

    #[test]
    fn descriptor_is_replaceable_and_requires_portal() {
        let descriptor = creem_provider_descriptor();
        descriptor.validate().unwrap();
        assert_eq!(descriptor.kind, ProviderKind::Commerce);
        assert!(descriptor.capabilities.contains(CUSTOMER_PORTAL_CAPABILITY));
        assert_eq!(descriptor.capabilities.len(), 6);
    }

    #[test]
    fn all_creem_secrets_stay_out_of_public_configuration() {
        let descriptor = creem_provider_descriptor();
        assert!(
            descriptor
                .configuration_schema
                .public_fields
                .iter()
                .all(|field| {
                    !field.id.to_ascii_lowercase().contains("secret")
                        && !field.id.to_ascii_lowercase().contains("key")
                })
        );
        assert_eq!(descriptor.configuration_schema.sensitive_fields.len(), 3);
    }
}

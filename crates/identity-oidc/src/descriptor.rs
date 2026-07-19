use agent_devkit::{
    ConfigFieldDescriptor, ConfigFieldType, HostPlatform, ProtocolCompatibility,
    ProviderConfigurationSchema, ProviderDescriptor, ProviderKind,
};
use semver::{Version, VersionReq};
use serde_json::json;
use std::collections::BTreeSet;
use url::Url;

pub const OIDC_IDENTITY_PROVIDER_ID: &str = "agentweave.identity.oidc";

pub fn oidc_identity_provider_descriptor() -> ProviderDescriptor {
    ProviderDescriptor {
        schema_version: 1,
        package_id: "agentweave-identity-oidc".into(),
        provider_id: OIDC_IDENTITY_PROVIDER_ID.into(),
        provider_version: Version::parse(env!("CARGO_PKG_VERSION"))
            .expect("crate version must be valid semver"),
        protocol_compatibility: ProtocolCompatibility {
            requirement: VersionReq::parse(">=0.1.0, <0.2.0")
                .expect("static protocol requirement must be valid"),
        },
        kind: ProviderKind::Identity,
        display_name: "OpenID Connect".into(),
        description: "Connects a developer-selected OIDC user service through native PKCE login."
            .into(),
        documentation_url: Url::parse("https://openid.net/developers/how-connect-works/")
            .expect("static documentation URL must be valid"),
        risk_notice:
            "Issuer metadata and callback URLs must exactly match the selected user service.".into(),
        platforms: BTreeSet::from([
            HostPlatform::Macos,
            HostPlatform::Windows,
            HostPlatform::Linux,
            HostPlatform::Android,
            HostPlatform::Ios,
            HostPlatform::Server,
        ]),
        capabilities: BTreeSet::from([
            "authorization_code_pkce".into(),
            "gateway_access_assertion".into(),
            "logout".into(),
            "refresh".into(),
        ]),
        configuration_schema: ProviderConfigurationSchema {
            schema_version: 1,
            migration_version: 1,
            public_fields: vec![
                select_field(
                    "preset",
                    "Provider preset",
                    "Select Generic OIDC, Auth0, Clerk, Supabase, or Cloudflare Access.",
                    &["generic", "auth0", "clerk", "supabase", "cloudflare_access"],
                ),
                url_field("issuer", "Issuer URL", "OIDC issuer used for discovery."),
                string_field(
                    "clientId",
                    "Client ID",
                    "Public native application client ID.",
                ),
                string_field(
                    "audience",
                    "Gateway audience",
                    "Audience or RFC 8707 resource expected by the model gateway.",
                ),
                ConfigFieldDescriptor {
                    id: "scopes".into(),
                    label: "Scopes".into(),
                    description: "OIDC scopes; openid is always required.".into(),
                    field_type: ConfigFieldType::StringList,
                    required: true,
                    default_value: Some(json!(["openid", "profile", "offline_access"])),
                    allowed_values: Vec::new(),
                    minimum_length: None,
                    maximum_length: None,
                    advanced: false,
                    visible_when: None,
                },
                url_field(
                    "redirectUri",
                    "Login callback",
                    "Exact callback URI registered with the identity service.",
                ),
                ConfigFieldDescriptor {
                    id: "gatewayAlgorithm".into(),
                    label: "Gateway signing algorithm".into(),
                    description: "JWT signature algorithm accepted by the model gateway.".into(),
                    field_type: ConfigFieldType::String,
                    required: false,
                    default_value: Some(json!("RS256")),
                    allowed_values: vec![json!("RS256"), json!("ES256")],
                    minimum_length: None,
                    maximum_length: None,
                    advanced: true,
                    visible_when: None,
                },
                optional_string_field(
                    "gatewayAudience",
                    "Gateway token audience",
                    "Override only when the access token audience differs from the OAuth resource.",
                ),
                optional_string_field(
                    "gatewayTenantClaim",
                    "Tenant claim",
                    "Optional verified JWT claim used for tenant isolation.",
                ),
                ConfigFieldDescriptor {
                    id: "gatewayDeviceMode".into(),
                    label: "Verified device mode".into(),
                    description: "Whether a signed device claim is required by the gateway.".into(),
                    field_type: ConfigFieldType::String,
                    required: false,
                    default_value: Some(json!("disabled")),
                    allowed_values: vec![
                        json!("required_verified"),
                        json!("optional_verified"),
                        json!("disabled"),
                    ],
                    minimum_length: None,
                    maximum_length: None,
                    advanced: true,
                    visible_when: None,
                },
                optional_string_field(
                    "gatewayDeviceClaim",
                    "Device claim",
                    "Signed JWT claim used only when verified device mode is enabled.",
                ),
                optional_string_field(
                    "gatewayRolesClaim",
                    "Roles claim",
                    "Optional signed JWT claim projected as user roles.",
                ),
                ConfigFieldDescriptor {
                    id: "gatewayRequireNbf".into(),
                    label: "Require not-before claim".into(),
                    description: "Reject gateway assertions that omit nbf.".into(),
                    field_type: ConfigFieldType::Boolean,
                    required: false,
                    default_value: Some(json!(false)),
                    allowed_values: Vec::new(),
                    minimum_length: None,
                    maximum_length: None,
                    advanced: true,
                    visible_when: None,
                },
            ],
            sensitive_fields: Vec::new(),
            cross_field_rules: Vec::new(),
        },
        developer_authorization_schema: None,
    }
}

fn string_field(id: &str, label: &str, description: &str) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        id: id.into(),
        label: label.into(),
        description: description.into(),
        field_type: ConfigFieldType::String,
        required: true,
        default_value: None,
        allowed_values: Vec::new(),
        minimum_length: Some(1),
        maximum_length: Some(2048),
        advanced: false,
        visible_when: None,
    }
}

fn optional_string_field(id: &str, label: &str, description: &str) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        required: false,
        advanced: true,
        ..string_field(id, label, description)
    }
}

fn url_field(id: &str, label: &str, description: &str) -> ConfigFieldDescriptor {
    let field_type = if id == "redirectUri" {
        ConfigFieldType::Url
    } else {
        ConfigFieldType::HttpsUrl
    };
    ConfigFieldDescriptor {
        field_type,
        ..string_field(id, label, description)
    }
}

fn select_field(
    id: &str,
    label: &str,
    description: &str,
    values: &[&str],
) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        allowed_values: values.iter().map(|value| json!(value)).collect(),
        ..string_field(id, label, description)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn descriptor_uses_the_common_plugin_contract() {
        let descriptor = oidc_identity_provider_descriptor();

        descriptor.validate().unwrap();
        assert_eq!(descriptor.kind, ProviderKind::Identity);
        assert!(descriptor.configuration_schema.sensitive_fields.is_empty());
        assert!(
            descriptor
                .configuration_schema
                .public_fields
                .iter()
                .all(|field| !field.id.contains("secret") && !field.id.contains("token"))
        );
    }
}

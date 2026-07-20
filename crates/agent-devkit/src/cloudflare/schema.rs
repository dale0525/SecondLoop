use super::{
    CAPABILITY_ACCOUNT_SETTINGS_READ, CAPABILITY_D1_READ, CAPABILITY_D1_WRITE,
    CAPABILITY_USER_DETAILS_READ, CAPABILITY_WORKERS_SCRIPTS_READ,
    CAPABILITY_WORKERS_SCRIPTS_WRITE, CLOUDFLARE_PROVIDER_ID,
};
use crate::{
    AuthorizationCapabilityRequirement, ConfigFieldDescriptor, ConfigFieldType, DevkitError,
    DevkitErrorCode, DevkitResult, HostPlatform, ProtocolCompatibility,
    ProviderConfigurationSchema, ProviderDescriptor, ProviderKind, SensitiveFieldDescriptor,
};
use semver::{Version, VersionReq};
use serde_json::json;
use std::collections::BTreeSet;
use url::Url;

pub fn cloudflare_gateway_provider_descriptor() -> DevkitResult<ProviderDescriptor> {
    Ok(ProviderDescriptor {
        schema_version: 1,
        package_id: "agentweave-cloudflare-gateway".into(),
        provider_id: CLOUDFLARE_PROVIDER_ID.into(),
        provider_version: Version::parse("0.1.0").map_err(|_| {
            DevkitError::new(DevkitErrorCode::Internal, "provider version is invalid")
        })?,
        protocol_compatibility: ProtocolCompatibility {
            requirement: VersionReq::parse(">=0.1.0, <0.2.0").map_err(|_| {
                DevkitError::new(DevkitErrorCode::Internal, "protocol range is invalid")
            })?,
        },
        kind: ProviderKind::GatewayDeployment,
        display_name: "Cloudflare Workers".into(),
        description: "Deploys an AgentWeave model gateway to a developer-owned Worker.".into(),
        documentation_url: Url::parse("https://developers.cloudflare.com/workers/").map_err(
            |_| DevkitError::new(DevkitErrorCode::Internal, "documentation URL is invalid"),
        )?,
        risk_notice: "Deployment can create, update, rotate, and delete remote resources.".into(),
        platforms: BTreeSet::from([
            HostPlatform::Macos,
            HostPlatform::Windows,
            HostPlatform::Linux,
        ]),
        capabilities: BTreeSet::from([
            CAPABILITY_ACCOUNT_SETTINGS_READ.into(),
            CAPABILITY_USER_DETAILS_READ.into(),
            CAPABILITY_WORKERS_SCRIPTS_READ.into(),
            CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
            CAPABILITY_D1_READ.into(),
            CAPABILITY_D1_WRITE.into(),
        ]),
        configuration_schema: gateway_project_schema(),
        developer_authorization_schema: Some(developer_authorization_schema()),
    })
}

fn gateway_project_schema() -> ProviderConfigurationSchema {
    ProviderConfigurationSchema {
        schema_version: 1,
        migration_version: 1,
        public_fields: vec![
            ConfigFieldDescriptor {
                field_type: ConfigFieldType::HttpsUrl,
                ..public_string_field(
                    "upstreamBaseUrl",
                    "Upstream model URL",
                    "HTTPS base URL used only by the deployed gateway.",
                    8,
                    2048,
                )
            },
            ConfigFieldDescriptor {
                id: "upstreamAuthentication".into(),
                label: "Upstream authentication".into(),
                description: "How the gateway presents the upstream model credential.".into(),
                field_type: ConfigFieldType::String,
                required: true,
                default_value: Some(json!("bearer")),
                allowed_values: vec![json!("bearer"), json!("x_api_key"), json!("api_key")],
                minimum_length: None,
                maximum_length: None,
                advanced: false,
                visible_when: None,
            },
            integer_field("maxBodyBytes", "Maximum request bytes", 4_194_304, false),
            integer_field("maxOutputTokens", "Maximum output tokens", 16_384, false),
            integer_field("maxTools", "Maximum tools", 128, true),
            integer_field("requestBaseUnits", "Base usage units", 1, true),
            integer_field(
                "deploymentMaxRequests",
                "Deployment request ceiling",
                10_000_000,
                true,
            ),
            integer_field(
                "deploymentMaxUnits",
                "Deployment usage ceiling",
                1_000_000_000_000_i64,
                true,
            ),
            integer_field("deploymentConcurrency", "Deployment concurrency", 100, true),
            integer_field("tenantConcurrency", "Tenant concurrency", 20, true),
            integer_field("deviceConcurrency", "Device concurrency", 1, true),
        ],
        sensitive_fields: vec![SensitiveFieldDescriptor {
            id: "upstreamApiKey".into(),
            label: "Upstream API key".into(),
            description: "Written directly to the Worker secret binding and never packaged.".into(),
            required: true,
            purpose: "model_upstream_authorization".into(),
            rotation_supported: true,
            visible_when: None,
        }],
        cross_field_rules: Vec::new(),
    }
}

fn developer_authorization_schema() -> ProviderConfigurationSchema {
    ProviderConfigurationSchema {
            schema_version: 1,
            migration_version: 1,
            public_fields: vec![
                public_optional_string_field(
                    "account-id",
                    "Cloudflare account",
                    "Deprecated preselection; the Host binds an account after OAuth.",
                    1,
                    256,
                ),
                public_string_field(
                    "client-id",
                    "OAuth client ID",
                    "Registered Cloudflare public OAuth client ID.",
                    1,
                    2048,
                ),
                ConfigFieldDescriptor {
                    id: "callback-uri".into(),
                    label: "OAuth callback".into(),
                    description: "Pre-registered HTTPS or fixed loopback callback generated by the Host.".into(),
                    field_type: ConfigFieldType::Url,
                    required: true,
                    default_value: None,
                    allowed_values: Vec::new(),
                    minimum_length: Some(8),
                    maximum_length: Some(4096),
                    advanced: false,
                    visible_when: None,
                },
                ConfigFieldDescriptor {
                    id: "scope-catalog".into(),
                    label: "OAuth scope catalog".into(),
                    description: "Authoritative scope-name to scope-ID mapping captured when the registered OAuth client is configured.".into(),
                    field_type: ConfigFieldType::StringMap,
                    required: true,
                    default_value: None,
                    allowed_values: Vec::new(),
                    minimum_length: None,
                    maximum_length: None,
                    advanced: true,
                    visible_when: None,
                },
            ],
            sensitive_fields: Vec::new(),
            cross_field_rules: Vec::new(),
    }
}

fn integer_field(
    id: &str,
    label: &str,
    default_value: i64,
    advanced: bool,
) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        id: id.into(),
        label: label.into(),
        description: "Positive bounded integer enforced by the deployed gateway.".into(),
        field_type: ConfigFieldType::Integer,
        required: true,
        default_value: Some(json!(default_value)),
        allowed_values: Vec::new(),
        minimum_length: None,
        maximum_length: None,
        advanced,
        visible_when: None,
    }
}

fn public_string_field(
    id: &str,
    label: &str,
    description: &str,
    minimum_length: usize,
    maximum_length: usize,
) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        id: id.into(),
        label: label.into(),
        description: description.into(),
        field_type: ConfigFieldType::String,
        required: true,
        default_value: None,
        allowed_values: Vec::new(),
        minimum_length: Some(minimum_length),
        maximum_length: Some(maximum_length),
        advanced: false,
        visible_when: None,
    }
}

fn public_optional_string_field(
    id: &str,
    label: &str,
    description: &str,
    minimum_length: usize,
    maximum_length: usize,
) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        required: false,
        ..public_string_field(id, label, description, minimum_length, maximum_length)
    }
}

pub(super) fn cloudflare_capability_requirements() -> Vec<AuthorizationCapabilityRequirement> {
    vec![
        AuthorizationCapabilityRequirement {
            capability: CAPABILITY_ACCOUNT_SETTINGS_READ.into(),
            accepted_catalog_names: BTreeSet::from(["Account Settings Read".into()]),
            reason: "Discover the Cloudflare accounts visible to the developer grant.".into(),
        },
        AuthorizationCapabilityRequirement {
            capability: CAPABILITY_USER_DETAILS_READ.into(),
            accepted_catalog_names: BTreeSet::from(["User Details Read".into()]),
            reason: "Attribute the developer grant to the authorizing Cloudflare user.".into(),
        },
        AuthorizationCapabilityRequirement {
            capability: CAPABILITY_WORKERS_SCRIPTS_READ.into(),
            accepted_catalog_names: BTreeSet::from(["Workers Scripts Read".into()]),
            reason: "Inspect deployments and detect drift before every mutation.".into(),
        },
        AuthorizationCapabilityRequirement {
            capability: CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
            accepted_catalog_names: BTreeSet::from(["Workers Scripts Write".into()]),
            reason: "Create versions, deployments, and Worker secret bindings.".into(),
        },
        AuthorizationCapabilityRequirement {
            capability: CAPABILITY_D1_READ.into(),
            accepted_catalog_names: BTreeSet::from(["D1 Read".into()]),
            reason: "Inspect the gateway entitlement ledger before planning a mutation.".into(),
        },
        AuthorizationCapabilityRequirement {
            capability: CAPABILITY_D1_WRITE.into(),
            accepted_catalog_names: BTreeSet::from(["D1 Write".into()]),
            reason: "Create and migrate the gateway entitlement ledger.".into(),
        },
    ]
}

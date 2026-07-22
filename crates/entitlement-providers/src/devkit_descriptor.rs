use crate::{
    CLOUDFLARE_POLICY_ENTITLEMENT_PROVIDER_ID, GATEWAY_POLICY_PROJECTION_CAPABILITY,
    GATEWAY_POLICY_PROJECTION_V2_CAPABILITY, HTTP_ENTITLEMENT_PROVIDER_ID,
    STATIC_ENTITLEMENT_PROVIDER_ID, STRIPE_PROJECTION_PROVIDER_ID,
};
use agent_devkit::{
    ConfigFieldDescriptor, ConfigFieldType, HostPlatform, ProtocolCompatibility,
    ProviderConfigurationSchema, ProviderDescriptor, ProviderKind, SensitiveFieldDescriptor,
};
use semver::{Version, VersionReq};
use serde_json::json;
use std::collections::BTreeSet;
use url::Url;

pub fn entitlement_provider_descriptors() -> Vec<ProviderDescriptor> {
    vec![
        static_descriptor(),
        http_descriptor(),
        cloudflare_policy_descriptor(),
        stripe_descriptor(),
    ]
}

fn cloudflare_policy_descriptor() -> ProviderDescriptor {
    let mut descriptor = base_descriptor(
        CLOUDFLARE_POLICY_ENTITLEMENT_PROVIDER_ID,
        "Cloudflare managed entitlement policy",
        "Projects signed entitlement policy from a separately deployed managed Worker.",
    );
    descriptor.capabilities = BTreeSet::from([
        "remote".into(),
        GATEWAY_POLICY_PROJECTION_CAPABILITY.into(),
        GATEWAY_POLICY_PROJECTION_V2_CAPABILITY.into(),
    ]);
    descriptor.configuration_schema.public_fields = vec![ConfigFieldDescriptor {
        field_type: ConfigFieldType::HttpsUrl,
        required: true,
        ..string_field(
            "baseUrl",
            "Managed policy URL",
            "Automatically resolved from the verified Cloudflare entitlement Worker.",
        )
    }];
    descriptor.configuration_schema.sensitive_fields = Vec::new();
    descriptor.risk_notice = "The managed policy Worker fails closed. Its signing secret is generated and stored only by the trusted Host and Cloudflare Workers."
        .into();
    descriptor
}

fn base_descriptor(provider_id: &str, display_name: &str, description: &str) -> ProviderDescriptor {
    ProviderDescriptor {
        schema_version: 1,
        package_id: "agentweave-entitlement-providers".into(),
        provider_id: provider_id.into(),
        provider_version: Version::parse(env!("CARGO_PKG_VERSION"))
            .expect("crate version must be valid semver"),
        protocol_compatibility: ProtocolCompatibility {
            requirement: VersionReq::parse(">=0.1.0, <0.2.0")
                .expect("static protocol requirement must be valid"),
        },
        kind: ProviderKind::Entitlement,
        display_name: display_name.into(),
        description: description.into(),
        documentation_url: Url::parse("https://github.com/dale0525/agentweave")
            .expect("static documentation URL must be valid"),
        risk_notice: "Entitlement failures deny model usage; production providers must use durable authoritative state."
            .into(),
        platforms: BTreeSet::from([
            HostPlatform::Macos,
            HostPlatform::Windows,
            HostPlatform::Linux,
            HostPlatform::Server,
        ]),
        capabilities: BTreeSet::from([
            "atomic_reservation".into(),
            "idempotent_settlement".into(),
        ]),
        configuration_schema: ProviderConfigurationSchema {
            schema_version: 1,
            migration_version: 1,
            public_fields: Vec::new(),
            sensitive_fields: Vec::new(),
            cross_field_rules: Vec::new(),
        },
        developer_authorization_schema: None,
    }
}

fn static_descriptor() -> ProviderDescriptor {
    let mut descriptor = base_descriptor(
        STATIC_ENTITLEMENT_PROVIDER_ID,
        "Static development entitlements",
        "Fixed allow or deny policy with process-local atomic quotas.",
    );
    descriptor.risk_notice =
        "Process-local quotas are not durable and must not protect a paid public deployment."
            .into();
    descriptor.capabilities.insert("offline".into());
    descriptor.configuration_schema.public_fields = vec![
        ConfigFieldDescriptor {
            id: "allow".into(),
            label: "Allow model use".into(),
            description: "Fixed decision for this development provider.".into(),
            field_type: ConfigFieldType::Boolean,
            required: true,
            default_value: Some(json!(true)),
            allowed_values: Vec::new(),
            minimum_length: None,
            maximum_length: None,
            advanced: false,
            visible_when: None,
        },
        ConfigFieldDescriptor {
            id: "quota".into(),
            label: "Quota dimensions".into(),
            description: "Positive integer limits keyed by usage dimension.".into(),
            field_type: ConfigFieldType::IntegerMap,
            required: true,
            default_value: Some(json!({"requests": 1000, "tokens": 1000000})),
            allowed_values: Vec::new(),
            minimum_length: None,
            maximum_length: None,
            advanced: false,
            visible_when: None,
        },
        integer_field("reservationTtlSeconds", "Reservation lifetime", 300),
    ];
    descriptor
}

fn http_descriptor() -> ProviderDescriptor {
    let mut descriptor = base_descriptor(
        HTTP_ENTITLEMENT_PROVIDER_ID,
        "Developer service entitlements",
        "Uses a fixed-origin HTTPS service owned by the app developer.",
    );
    descriptor.capabilities.insert("remote".into());
    descriptor
        .capabilities
        .insert(GATEWAY_POLICY_PROJECTION_CAPABILITY.into());
    descriptor.configuration_schema.public_fields = vec![
        ConfigFieldDescriptor {
            field_type: ConfigFieldType::HttpsUrl,
            ..string_field(
                "baseUrl",
                "Service URL",
                "Fixed HTTPS origin for reserve, commit, and release.",
            )
        },
        integer_field("timeoutMilliseconds", "Request timeout", 10000),
        integer_field("maxResponseBytes", "Response limit", 65536),
    ];
    descriptor.configuration_schema.sensitive_fields = vec![SensitiveFieldDescriptor {
        id: "serviceCredential".into(),
        label: "Service credential".into(),
        description: "Host-vault credential sent only to the configured entitlement service."
            .into(),
        required: true,
        purpose: "entitlement_service_authorization".into(),
        rotation_supported: true,
        visible_when: None,
    }];
    descriptor
}

fn stripe_descriptor() -> ProviderDescriptor {
    let mut descriptor = base_descriptor(
        STRIPE_PROJECTION_PROVIDER_ID,
        "Stripe entitlement projection",
        "Consumes subscription facts already verified by a developer backend.",
    );
    descriptor
        .capabilities
        .insert("backend_verified_projection".into());
    descriptor.configuration_schema.public_fields = vec![
        string_field(
            "projectionSourceId",
            "Projection source",
            "Trusted Host source for already verified entitlement facts.",
        ),
        integer_field("reservationTtlSeconds", "Reservation lifetime", 300),
        integer_field("maxProjectionAgeSeconds", "Maximum projection age", 300),
    ];
    descriptor
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

fn integer_field(id: &str, label: &str, default_value: u64) -> ConfigFieldDescriptor {
    ConfigFieldDescriptor {
        id: id.into(),
        label: label.into(),
        description: "Positive bounded integer configured by the developer.".into(),
        field_type: ConfigFieldType::Integer,
        required: true,
        default_value: Some(json!(default_value)),
        allowed_values: Vec::new(),
        minimum_length: None,
        maximum_length: None,
        advanced: true,
        visible_when: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_entitlement_plugins_use_the_common_descriptor_contract() {
        let descriptors = entitlement_provider_descriptors();

        assert_eq!(descriptors.len(), 4);
        for descriptor in descriptors {
            descriptor.validate().unwrap();
            assert_eq!(descriptor.kind, ProviderKind::Entitlement);
        }
    }

    #[test]
    fn http_service_credential_is_not_public_configuration() {
        let descriptor = http_descriptor();

        assert!(
            descriptor
                .configuration_schema
                .public_fields
                .iter()
                .all(|field| {
                    !field.id.contains("secret")
                        && !field.id.contains("credential")
                        && !field.id.contains("token")
                })
        );
        assert_eq!(descriptor.configuration_schema.sensitive_fields.len(), 1);
    }
}

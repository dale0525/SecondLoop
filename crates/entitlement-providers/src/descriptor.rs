use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeSet;

pub const ENTITLEMENT_PROVIDER_DESCRIPTOR_SCHEMA_VERSION: u32 = 1;
pub const STATIC_ENTITLEMENT_PROVIDER_ID: &str = "agentweave.entitlements.static";
pub const HTTP_ENTITLEMENT_PROVIDER_ID: &str = "agentweave.entitlements.http";
pub const CLOUDFLARE_POLICY_ENTITLEMENT_PROVIDER_ID: &str =
    "agentweave.entitlements.cloudflare_policy";
pub const STRIPE_PROJECTION_PROVIDER_ID: &str = "agentweave.entitlements.stripe_projection";

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementProviderImplementationKind {
    Static,
    Http,
    StripeProjection,
}

/// Machine-readable metadata used by developer tooling to render provider selection and config.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementProviderDescriptor {
    pub schema_version: u32,
    pub provider_id: String,
    pub implementation_kind: EntitlementProviderImplementationKind,
    pub display_name: String,
    pub description: String,
    pub risk_notice: String,
    pub capabilities: BTreeSet<String>,
    /// JSON Schema Draft 2020-12 for the provider's non-secret configuration.
    pub configuration_schema: Value,
}

pub fn builtin_entitlement_provider_descriptors() -> Vec<EntitlementProviderDescriptor> {
    vec![
        static_entitlement_provider_descriptor(),
        http_entitlement_provider_descriptor(),
        stripe_projection_provider_descriptor(),
    ]
}

pub fn static_entitlement_provider_descriptor() -> EntitlementProviderDescriptor {
    descriptor(
        STATIC_ENTITLEMENT_PROVIDER_ID,
        EntitlementProviderImplementationKind::Static,
        "Static development entitlements",
        "Fixed allow/deny policy with process-local atomic quota accounting.",
        "In-memory quota is not durable and is intended only for development or controlled private deployments.",
        ["atomic_quota", "idempotent_settlement", "offline"],
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "additionalProperties": false,
            "required": ["allow", "quota"],
            "properties": {
                "allow": { "type": "boolean", "default": true },
                "quota": {
                    "type": "object",
                    "description": "Process-local quota per usage dimension.",
                    "propertyNames": { "pattern": "^[A-Za-z0-9._-]{1,255}$" },
                    "additionalProperties": { "type": "integer", "minimum": 1 }
                },
                "reservationTtlSeconds": {
                    "type": "integer", "minimum": 1, "maximum": 3600, "default": 300
                }
            }
        }),
    )
}

pub fn http_entitlement_provider_descriptor() -> EntitlementProviderDescriptor {
    descriptor(
        HTTP_ENTITLEMENT_PROVIDER_ID,
        EntitlementProviderImplementationKind::Http,
        "Developer service entitlements",
        "Fail-closed entitlement decisions and settlement through a fixed-origin HTTPS service.",
        "The referenced service credential is resolved by the host and must never be embedded in app configuration.",
        [
            "fixed_origin",
            "idempotent_settlement",
            "remote",
            "secret_reference",
        ],
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "additionalProperties": false,
            "required": ["baseUrl", "serviceSecretId"],
            "properties": {
                "baseUrl": {
                    "type": "string", "format": "uri",
                    "description": "Origin-only HTTPS URL; HTTP is accepted only for a loopback host."
                },
                "serviceSecretId": {
                    "type": "string", "minLength": 1, "maxLength": 255,
                    "description": "Opaque host-vault reference, never the credential value."
                },
                "timeoutMilliseconds": {
                    "type": "integer", "minimum": 100, "maximum": 60000, "default": 10000
                },
                "maxResponseBytes": {
                    "type": "integer", "minimum": 256, "maximum": 1048576, "default": 65536
                }
            }
        }),
    )
}

pub fn stripe_projection_provider_descriptor() -> EntitlementProviderDescriptor {
    descriptor(
        STRIPE_PROJECTION_PROVIDER_ID,
        EntitlementProviderImplementationKind::StripeProjection,
        "Stripe entitlement projection",
        "Projects developer-backend-verified subscription state into AgentWeave quota decisions.",
        "This reference provider does not store Stripe secrets or implement catalog, tax, payment, refund, or webhook verification workflows.",
        [
            "atomic_quota",
            "backend_verified_projection",
            "idempotent_settlement",
        ],
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "additionalProperties": false,
            "required": ["projectionSourceId"],
            "properties": {
                "projectionSourceId": {
                    "type": "string", "minLength": 1, "maxLength": 255,
                    "description": "Trusted host source that returns already verified entitlement projections."
                },
                "reservationTtlSeconds": {
                    "type": "integer", "minimum": 1, "maximum": 3600, "default": 300
                },
                "maxProjectionAgeSeconds": {
                    "type": "integer", "minimum": 1, "maximum": 86400, "default": 300
                }
            }
        }),
    )
}

fn descriptor<const N: usize>(
    provider_id: &str,
    implementation_kind: EntitlementProviderImplementationKind,
    display_name: &str,
    description: &str,
    risk_notice: &str,
    capabilities: [&str; N],
    configuration_schema: Value,
) -> EntitlementProviderDescriptor {
    EntitlementProviderDescriptor {
        schema_version: ENTITLEMENT_PROVIDER_DESCRIPTOR_SCHEMA_VERSION,
        provider_id: provider_id.into(),
        implementation_kind,
        display_name: display_name.into(),
        description: description.into(),
        risk_notice: risk_notice.into(),
        capabilities: capabilities.into_iter().map(str::to_owned).collect(),
        configuration_schema,
    }
}

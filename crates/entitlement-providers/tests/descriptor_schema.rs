use entitlement_providers::{
    ENTITLEMENT_PROVIDER_DESCRIPTOR_SCHEMA_VERSION, EntitlementProviderDescriptor,
    HTTP_ENTITLEMENT_PROVIDER_ID, HttpEntitlementConfig, STATIC_ENTITLEMENT_PROVIDER_ID,
    STRIPE_PROJECTION_PROVIDER_ID, StaticEntitlementConfig, StripeProjectionConfig,
    builtin_entitlement_provider_descriptors,
};
use serde_json::json;
use std::collections::BTreeSet;

#[test]
fn builtin_descriptors_are_unique_machine_readable_json_schemas() {
    let descriptors = builtin_entitlement_provider_descriptors();
    assert_eq!(descriptors.len(), 3);
    let ids = descriptors
        .iter()
        .map(|descriptor| descriptor.provider_id.as_str())
        .collect::<BTreeSet<_>>();
    assert_eq!(
        ids,
        BTreeSet::from([
            HTTP_ENTITLEMENT_PROVIDER_ID,
            STATIC_ENTITLEMENT_PROVIDER_ID,
            STRIPE_PROJECTION_PROVIDER_ID,
        ])
    );
    for descriptor in descriptors {
        assert_eq!(
            descriptor.schema_version,
            ENTITLEMENT_PROVIDER_DESCRIPTOR_SCHEMA_VERSION
        );
        assert_eq!(
            descriptor.configuration_schema["$schema"],
            "https://json-schema.org/draft/2020-12/schema"
        );
        assert_eq!(descriptor.configuration_schema["type"], "object");
        assert_eq!(
            descriptor.configuration_schema["additionalProperties"],
            false
        );
        assert!(!descriptor.capabilities.is_empty());

        let encoded = serde_json::to_value(&descriptor).unwrap();
        let decoded: EntitlementProviderDescriptor = serde_json::from_value(encoded).unwrap();
        assert_eq!(decoded, descriptor);
    }
}

#[test]
fn schemas_expose_only_non_secret_configuration() {
    let encoded = serde_json::to_string(&builtin_entitlement_provider_descriptors()).unwrap();
    for forbidden in [
        "stripeSecretKey",
        "stripeWebhookSecret",
        "apiKey",
        "bearerToken",
        "authorizationHeader",
    ] {
        assert!(!encoded.contains(forbidden));
    }
    assert!(encoded.contains("serviceSecretId"));
    assert!(encoded.contains("projectionSourceId"));
}

#[test]
fn typed_configs_apply_defaults_and_deny_unknown_fields() {
    let static_config: StaticEntitlementConfig = serde_json::from_value(json!({
        "allow": true,
        "quota": { "requests": 10 }
    }))
    .unwrap();
    assert_eq!(static_config.reservation_ttl_seconds, 300);
    assert!(static_config.validate().is_ok());

    let http_config: HttpEntitlementConfig = serde_json::from_value(json!({
        "baseUrl": "https://entitlements.example.test/",
        "serviceSecretId": "vault:entitlement-service"
    }))
    .unwrap();
    assert_eq!(http_config.timeout_milliseconds, 10_000);
    assert_eq!(http_config.max_response_bytes, 65_536);
    assert!(http_config.validate().is_ok());

    let projection_config: StripeProjectionConfig = serde_json::from_value(json!({
        "projectionSourceId": "developer-backend-projection"
    }))
    .unwrap();
    assert_eq!(projection_config.reservation_ttl_seconds, 300);
    assert_eq!(projection_config.max_projection_age_seconds, 300);
    assert!(projection_config.validate().is_ok());

    assert!(
        serde_json::from_value::<HttpEntitlementConfig>(json!({
            "baseUrl": "https://entitlements.example.test/",
            "serviceSecretId": "vault:entitlement-service",
            "unexpected": true
        }))
        .is_err()
    );
}

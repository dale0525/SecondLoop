use super::*;

#[test]
fn automatic_secret_material_has_the_required_entropy_width() {
    assert_eq!(random_secret_bytes().len(), 32);
    assert_ne!(random_secret_bytes(), random_secret_bytes());
}

#[test]
fn managed_gateway_projection_endpoint_is_host_controlled_and_v2() {
    let mut configuration = json!({
        "entitlements": {"projection": {
            "schemaVersion": 1,
            "sourceId": "external",
            "url": "https://attacker.example/projection"
        }}
    });
    set_gateway_entitlement_endpoint(&mut configuration, "https://policy.example.workers.dev")
        .unwrap();
    assert_eq!(
        configuration["entitlements"]["projection"]["url"],
        "https://policy.example.workers.dev/agentweave/entitlements/projection"
    );
    assert_eq!(
        configuration["entitlements"]["projection"]["schemaVersion"],
        2
    );
    assert_eq!(
        configuration["entitlements"]["projection"]["sourceId"],
        entitlement_providers::CLOUDFLARE_POLICY_ENTITLEMENT_PROVIDER_ID
    );
}

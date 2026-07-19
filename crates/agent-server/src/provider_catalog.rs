use agent_devkit::{ProviderDescriptor, ProviderKind};
use semver::Version;
use std::collections::{BTreeMap, BTreeSet};

pub fn builtin_provider_catalog() -> anyhow::Result<Vec<ProviderDescriptor>> {
    let mut descriptors = entitlement_providers::entitlement_provider_descriptors();
    descriptors.push(identity_oidc::oidc_identity_provider_descriptor());
    descriptors.push(agent_devkit::cloudflare::cloudflare_gateway_provider_descriptor()?);
    descriptors.sort_by(|left, right| left.provider_id.cmp(&right.provider_id));

    let mut ids = BTreeSet::new();
    for descriptor in &descriptors {
        descriptor.validate()?;
        anyhow::ensure!(
            ids.insert(descriptor.provider_id.as_str()),
            "built-in provider identifiers must be unique"
        );
    }
    Ok(descriptors)
}

pub fn runtime_provider_versions() -> anyhow::Result<BTreeMap<String, Version>> {
    Ok(builtin_provider_catalog()?
        .into_iter()
        .filter(|descriptor| descriptor.kind != ProviderKind::GatewayDeployment)
        .map(|descriptor| (descriptor.provider_id, descriptor.provider_version))
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_inventory_excludes_developer_deployment_plugins() {
        let providers = runtime_provider_versions().unwrap();

        assert!(providers.contains_key(identity_oidc::OIDC_IDENTITY_PROVIDER_ID));
        assert!(providers.contains_key(entitlement_providers::HTTP_ENTITLEMENT_PROVIDER_ID));
        assert!(!providers.contains_key(agent_devkit::cloudflare::CLOUDFLARE_PROVIDER_ID));
    }
}

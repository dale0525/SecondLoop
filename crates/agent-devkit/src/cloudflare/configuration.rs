use super::{
    CloudflareOAuthScope, CloudflareOAuthScopeCatalog, oauth::validate_cloudflare_redirect_uri,
};
use crate::{DevkitError, DevkitResult, ProviderConfiguration, ProviderDescriptor};
use serde_json::Value;
use std::collections::BTreeSet;
use url::Url;

pub(super) struct CloudflareProviderConfiguration {
    pub oauth_client_id: String,
    pub oauth_redirect_uri: Url,
    pub scope_catalog: CloudflareOAuthScopeCatalog,
}

pub(super) fn parse_cloudflare_configuration(
    descriptor: &ProviderDescriptor,
    configuration: &ProviderConfiguration,
) -> DevkitResult<CloudflareProviderConfiguration> {
    configuration.validate_developer_authorization_against(descriptor)?;
    let string = |key: &str| {
        configuration
            .public
            .get(key)
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| {
                DevkitError::invalid_configuration(format!(
                    "Cloudflare configuration field is missing: {key}"
                ))
            })
    };
    let redirect_uri = Url::parse(&string("callback-uri")?).map_err(|_| {
        DevkitError::invalid_configuration("Cloudflare OAuth redirect URI is invalid")
    })?;
    validate_cloudflare_redirect_uri(&redirect_uri)?;
    let scope_catalog = configuration
        .public
        .get("scope-catalog")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            DevkitError::invalid_configuration(
                "Cloudflare OAuth scope catalog is missing or invalid",
            )
        })?
        .iter()
        .map(|(name, id)| {
            let id = id.as_str().ok_or_else(|| {
                DevkitError::invalid_configuration(
                    "Cloudflare OAuth scope catalog IDs must be strings",
                )
            })?;
            Ok(CloudflareOAuthScope {
                id: id.into(),
                authoritative_name: name.clone(),
                description: None,
            })
        })
        .collect::<DevkitResult<BTreeSet<_>>>()?;
    Ok(CloudflareProviderConfiguration {
        oauth_client_id: string("client-id")?,
        oauth_redirect_uri: redirect_uri,
        scope_catalog: CloudflareOAuthScopeCatalog::from_records(scope_catalog).map_err(|_| {
            DevkitError::invalid_configuration(
                "Cloudflare OAuth scope catalog contains invalid records",
            )
        })?,
    })
}

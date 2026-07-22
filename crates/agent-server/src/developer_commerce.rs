use crate::developer_control_plane::DeveloperControlPlane;
use agent_devkit::{DevkitError, DevkitErrorCode, DevkitResult};
use commerce_creem::{CreemApiKey, CreemClient, ReqwestCreemTransport};
use commerce_runtime::{CommerceEnvironment, CommerceError, CommerceProduct};
use serde::Serialize;
use std::sync::Arc;
use zeroize::Zeroizing;

const CREEM_API_KEY_BINDING: &str = "CREEM_API_KEY";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreemProductDiscoveryReceipt {
    pub environment: CommerceEnvironment,
    pub configured_revision: String,
    pub products: Vec<CommerceProduct>,
}

impl DeveloperControlPlane {
    pub async fn discover_creem_products(
        &self,
        environment: CommerceEnvironment,
        revision: String,
        api_key: Vec<u8>,
    ) -> DevkitResult<CreemProductDiscoveryReceipt> {
        let bytes = Zeroizing::new(api_key);
        let key = std::str::from_utf8(bytes.as_slice())
            .map_err(|_| DevkitError::invalid_configuration("Creem API key is invalid"))?
            .to_owned();
        self.resolve_sensitive_binding(CREEM_API_KEY_BINDING, &revision, Some(bytes.to_vec()))
            .await?;
        let transport = Arc::new(ReqwestCreemTransport::new().map_err(commerce_error)?);
        let client = CreemClient::new(
            environment,
            CreemApiKey::new(key).map_err(commerce_error)?,
            transport,
        );
        let products = client.list_products().await.map_err(commerce_error)?;
        Ok(CreemProductDiscoveryReceipt {
            environment,
            configured_revision: revision,
            products,
        })
    }
}

fn commerce_error(error: CommerceError) -> DevkitError {
    match error {
        CommerceError::AuthenticationRequired | CommerceError::ProviderRejected => {
            DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "Creem rejected the configured API key",
            )
        }
        CommerceError::Unavailable => DevkitError::new(
            DevkitErrorCode::Unavailable,
            "Creem product discovery is temporarily unavailable",
        ),
        CommerceError::EnvironmentMismatch => DevkitError::new(
            DevkitErrorCode::InvalidConfiguration,
            "Creem API key and environment do not match",
        ),
        CommerceError::InvalidResponse => DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Creem returned an invalid product response",
        ),
        _ => DevkitError::invalid_configuration("Creem product discovery request is invalid"),
    }
}

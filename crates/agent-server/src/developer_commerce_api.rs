use crate::api::AppState;
use crate::developer_control_plane_api::ControlPlaneApiError;
use axum::{Json, Router, extract::State, routing::post};
use commerce_runtime::CommerceEnvironment;
use serde::Deserialize;
use std::sync::Arc;
use zeroize::Zeroize;

const MAX_SECRET_BYTES: usize = 64 * 1024;

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new().route(
        "/dev/control/commerce/creem/products",
        post(discover_creem_products),
    )
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DiscoverCreemProductsRequest {
    environment: CommerceEnvironment,
    revision: String,
    api_key: SensitiveText,
}

async fn discover_creem_products(
    State(state): State<Arc<AppState>>,
    Json(request): Json<DiscoverCreemProductsRequest>,
) -> Result<Json<crate::developer_commerce::CreemProductDiscoveryReceipt>, ControlPlaneApiError> {
    let control = state.developer_control_plane().ok_or_else(|| {
        agent_devkit::DevkitError::new(
            agent_devkit::DevkitErrorCode::Unavailable,
            "Developer control plane is unavailable",
        )
    })?;
    Ok(Json(
        control
            .discover_creem_products(
                request.environment,
                request.revision,
                request.api_key.into_bytes(),
            )
            .await?,
    ))
}

struct SensitiveText(String);

impl<'de> Deserialize<'de> for SensitiveText {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        if !(16..=MAX_SECRET_BYTES).contains(&value.len()) || value.chars().any(char::is_control) {
            return Err(serde::de::Error::custom("Creem API key is invalid"));
        }
        Ok(Self(value))
    }
}

impl SensitiveText {
    fn into_bytes(mut self) -> Vec<u8> {
        std::mem::take(&mut self.0).into_bytes()
    }
}

impl Drop for SensitiveText {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

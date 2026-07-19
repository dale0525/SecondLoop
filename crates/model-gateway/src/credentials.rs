use async_trait::async_trait;
use std::fmt;
use zeroize::Zeroizing;

pub struct GatewayBearerToken(Zeroizing<String>);

impl GatewayBearerToken {
    pub fn new(value: impl Into<String>) -> Result<Self, GatewayCredentialError> {
        let value = value.into();
        if value.is_empty() || value.len() > 64 * 1024 || value.contains(['\r', '\n']) {
            return Err(GatewayCredentialError);
        }
        Ok(Self(Zeroizing::new(value)))
    }

    pub(crate) fn expose(&self) -> &str {
        self.0.as_str()
    }
}

impl fmt::Debug for GatewayBearerToken {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("GatewayBearerToken([REDACTED])")
    }
}

#[derive(Clone, Copy, Debug, thiserror::Error)]
#[error("gateway credential is unavailable")]
pub struct GatewayCredentialError;

#[async_trait]
pub trait GatewayCredentialProvider: Send + Sync {
    async fn bearer_token(&self) -> Result<GatewayBearerToken, GatewayCredentialError>;
}

use agent_runtime::identity::{IdentityProviderError, IdentityProviderErrorCode};
use thiserror::Error;

/// A deliberately non-diagnostic public error. Provider responses and secrets
/// are never included in display output or an error source chain.
#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
pub enum OidcError {
    #[error("OIDC configuration is invalid")]
    InvalidConfiguration,
    #[error("OIDC authorization request is invalid")]
    InvalidAuthorization,
    #[error("OIDC authorization is required")]
    AuthenticationRequired,
    #[error("OIDC authorization was denied")]
    AccessDenied,
    #[error("OIDC provider response is invalid")]
    InvalidProviderResponse,
    #[error("OIDC provider is unavailable")]
    Unavailable,
    #[error("OIDC session is busy")]
    SessionBusy,
    #[error("OIDC secure storage failed")]
    SecureStorage,
}

impl From<OidcError> for IdentityProviderError {
    fn from(error: OidcError) -> Self {
        let code = match error {
            OidcError::AuthenticationRequired => IdentityProviderErrorCode::AuthenticationRequired,
            OidcError::AccessDenied => IdentityProviderErrorCode::AccessDenied,
            OidcError::InvalidConfiguration | OidcError::InvalidAuthorization => {
                IdentityProviderErrorCode::InvalidRequest
            }
            OidcError::InvalidProviderResponse => IdentityProviderErrorCode::InvalidResponse,
            OidcError::Unavailable | OidcError::SessionBusy | OidcError::SecureStorage => {
                IdentityProviderErrorCode::Unavailable
            }
        };
        IdentityProviderError::new(code)
    }
}

impl From<IdentityProviderError> for OidcError {
    fn from(error: IdentityProviderError) -> Self {
        match error.code {
            IdentityProviderErrorCode::AuthenticationRequired => OidcError::AuthenticationRequired,
            IdentityProviderErrorCode::AccessDenied => OidcError::AccessDenied,
            IdentityProviderErrorCode::InvalidRequest => OidcError::InvalidAuthorization,
            IdentityProviderErrorCode::InvalidResponse => OidcError::InvalidProviderResponse,
            IdentityProviderErrorCode::Unavailable => OidcError::Unavailable,
        }
    }
}

pub(crate) type Result<T> = std::result::Result<T, OidcError>;

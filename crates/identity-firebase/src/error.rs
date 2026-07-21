use agent_runtime::identity::{IdentityProviderError, IdentityProviderErrorCode};
use thiserror::Error;

pub type Result<T> = std::result::Result<T, FirebaseError>;

#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
pub enum FirebaseError {
    #[error("Firebase configuration is invalid")]
    InvalidConfiguration,
    #[error("Firebase sign-in input is invalid")]
    InvalidRequest,
    #[error("Firebase authentication was denied")]
    AccessDenied,
    #[error("Firebase session requires authentication")]
    AuthenticationRequired,
    #[error("Firebase returned an invalid response")]
    InvalidResponse,
    #[error("Firebase is unavailable")]
    Unavailable,
    #[error("Firebase secure session storage is unavailable")]
    SecureStorage,
}

impl From<FirebaseError> for IdentityProviderError {
    fn from(error: FirebaseError) -> Self {
        let code = match error {
            FirebaseError::InvalidConfiguration | FirebaseError::InvalidRequest => {
                IdentityProviderErrorCode::InvalidRequest
            }
            FirebaseError::AccessDenied => IdentityProviderErrorCode::AccessDenied,
            FirebaseError::AuthenticationRequired => {
                IdentityProviderErrorCode::AuthenticationRequired
            }
            FirebaseError::InvalidResponse => IdentityProviderErrorCode::InvalidResponse,
            FirebaseError::Unavailable | FirebaseError::SecureStorage => {
                IdentityProviderErrorCode::Unavailable
            }
        };
        IdentityProviderError::new(code)
    }
}

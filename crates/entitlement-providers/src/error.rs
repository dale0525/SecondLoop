use thiserror::Error;

#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
pub enum EntitlementProviderConfigurationError {
    #[error("reservation TTL is outside the supported range")]
    InvalidReservationTtl,
    #[error("static quota is invalid")]
    InvalidStaticQuota,
    #[error("HTTP entitlement origin is invalid")]
    InvalidHttpOrigin,
    #[error("HTTP entitlement timeout is outside the supported range")]
    InvalidHttpTimeout,
    #[error("HTTP entitlement response limit is outside the supported range")]
    InvalidHttpResponseLimit,
    #[error("service secret reference is invalid")]
    InvalidSecretReference,
    #[error("HTTP entitlement transport initialization failed")]
    HttpTransportInitializationFailed,
    #[error("Stripe projection source is invalid")]
    InvalidProjectionSource,
    #[error("Stripe projection freshness is outside the supported range")]
    InvalidProjectionFreshness,
}

pub(crate) fn valid_opaque_reference(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 255
        && value == value.trim()
        && !value.chars().any(char::is_control)
}

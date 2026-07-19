use serde::{Deserialize, Serialize};
use std::fmt;

/// Stable, non-secret error classification suitable for Host-to-Renderer DTOs.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DevkitErrorCode {
    InvalidConfiguration,
    InvalidAuthorization,
    PermissionInsufficient,
    InvalidPlan,
    PlanIntegrityFailed,
    ConcurrentModification,
    NotFound,
    AlreadyExists,
    RateLimited,
    Timeout,
    Unavailable,
    RedirectRejected,
    OriginRejected,
    RemoteProtocol,
    DriftDetected,
    VerificationFailed,
    Unsupported,
    SensitiveInputUnavailable,
    Internal,
}

/// Whether a failed call may have changed the remote control plane.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RemoteMutationRisk {
    None,
    Possible,
}

/// Error payloads contain stable messages only. Upstream bodies and secrets are never retained.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct DevkitError {
    pub code: DevkitErrorCode,
    pub safe_message: String,
    pub retry_after_ms: Option<u64>,
    pub remote_mutation_risk: RemoteMutationRisk,
}

impl DevkitError {
    pub fn new(code: DevkitErrorCode, safe_message: impl Into<String>) -> Self {
        Self {
            code,
            safe_message: safe_message.into(),
            retry_after_ms: None,
            remote_mutation_risk: RemoteMutationRisk::None,
        }
    }

    pub fn retry_after(mut self, retry_after_ms: u64) -> Self {
        self.retry_after_ms = Some(retry_after_ms);
        self
    }

    pub fn with_remote_mutation_risk(mut self, risk: RemoteMutationRisk) -> Self {
        self.remote_mutation_risk = risk;
        self
    }

    pub fn invalid_configuration(message: impl Into<String>) -> Self {
        Self::new(DevkitErrorCode::InvalidConfiguration, message)
    }

    pub fn invalid_plan(message: impl Into<String>) -> Self {
        Self::new(DevkitErrorCode::InvalidPlan, message)
    }
}

impl fmt::Debug for DevkitError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DevkitError")
            .field("code", &self.code)
            .field("safe_message", &self.safe_message)
            .field("retry_after_ms", &self.retry_after_ms)
            .field("remote_mutation_risk", &self.remote_mutation_risk)
            .finish()
    }
}

impl fmt::Display for DevkitError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{} ({:?})", self.safe_message, self.code)
    }
}

impl std::error::Error for DevkitError {}

pub type DevkitResult<T> = Result<T, DevkitError>;

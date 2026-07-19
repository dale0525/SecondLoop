use crate::{DevkitError, DevkitErrorCode, DevkitResult};
use async_trait::async_trait;
use serde::{Deserialize, Deserializer, Serialize};
use std::fmt;
use zeroize::Zeroize;

/// Opaque reference to a value in a Host-owned secret store.
///
/// The reference is not the secret and cannot be resolved by Renderer code. Its debug output is
/// redacted because store identifiers can still reveal implementation details.
#[derive(Clone, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(transparent)]
pub struct SensitiveInputHandle(String);

impl SensitiveInputHandle {
    pub fn from_opaque_reference(reference: impl Into<String>) -> DevkitResult<Self> {
        let reference = reference.into();
        if reference.is_empty() || reference.len() > 512 || reference.chars().any(char::is_control)
        {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidConfiguration,
                "sensitive input handle is invalid",
            ));
        }
        Ok(Self(reference))
    }

    /// Only Host-side stores and transports should use the opaque reference.
    pub fn opaque_reference(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SensitiveInputHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SensitiveInputHandle([REDACTED])")
    }
}

impl<'de> Deserialize<'de> for SensitiveInputHandle {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let reference = String::deserialize(deserializer)?;
        Self::from_opaque_reference(reference).map_err(serde::de::Error::custom)
    }
}

/// A short-lived in-memory secret that is zeroized on drop.
pub struct SensitiveValue(Vec<u8>);

impl SensitiveValue {
    pub fn new(bytes: impl Into<Vec<u8>>) -> DevkitResult<Self> {
        let bytes = bytes.into();
        if bytes.is_empty() || bytes.len() > 1024 * 1024 {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidConfiguration,
                "sensitive input has an invalid size",
            ));
        }
        Ok(Self(bytes))
    }

    pub fn expose<T>(&self, operation: impl FnOnce(&[u8]) -> DevkitResult<T>) -> DevkitResult<T> {
        operation(&self.0)
    }
}

impl fmt::Debug for SensitiveValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SensitiveValue([REDACTED])")
    }
}

impl Drop for SensitiveValue {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

#[async_trait]
pub trait SensitiveInputResolver: Send + Sync {
    async fn resolve(&self, handle: &SensitiveInputHandle) -> DevkitResult<SensitiveValue>;
}

#[async_trait]
pub trait SensitiveInputStore: SensitiveInputResolver {
    async fn store(
        &self,
        namespace: &str,
        value: SensitiveValue,
    ) -> DevkitResult<SensitiveInputHandle>;
}

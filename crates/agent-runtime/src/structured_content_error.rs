use thiserror::Error;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StructuredContentErrorKind {
    Invalid,
    NotFound,
    Conflict,
    Expired,
}

#[derive(Debug, Error)]
#[error("{message}")]
pub struct StructuredContentError {
    kind: StructuredContentErrorKind,
    message: String,
}

impl StructuredContentError {
    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(StructuredContentErrorKind::Invalid, message)
    }

    pub fn not_found(message: impl Into<String>) -> Self {
        Self::new(StructuredContentErrorKind::NotFound, message)
    }

    pub fn conflict(message: impl Into<String>) -> Self {
        Self::new(StructuredContentErrorKind::Conflict, message)
    }

    pub fn expired(message: impl Into<String>) -> Self {
        Self::new(StructuredContentErrorKind::Expired, message)
    }

    pub fn kind(&self) -> StructuredContentErrorKind {
        self.kind
    }

    fn new(kind: StructuredContentErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }
}

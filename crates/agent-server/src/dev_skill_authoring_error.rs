use std::{error::Error, fmt};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DevSkillAuthoringErrorKind {
    BadRequest,
    NotFound,
    Conflict,
    Unprocessable,
}

#[derive(Debug)]
pub(crate) struct DevSkillAuthoringError {
    kind: DevSkillAuthoringErrorKind,
    message: String,
}

impl DevSkillAuthoringError {
    pub(crate) fn bad_request(message: impl Into<String>) -> Self {
        Self::new(DevSkillAuthoringErrorKind::BadRequest, message)
    }

    pub(crate) fn not_found(message: impl Into<String>) -> Self {
        Self::new(DevSkillAuthoringErrorKind::NotFound, message)
    }

    pub(crate) fn conflict(message: impl Into<String>) -> Self {
        Self::new(DevSkillAuthoringErrorKind::Conflict, message)
    }

    pub(crate) fn unprocessable(message: impl Into<String>) -> Self {
        Self::new(DevSkillAuthoringErrorKind::Unprocessable, message)
    }

    pub(crate) fn kind(&self) -> DevSkillAuthoringErrorKind {
        self.kind
    }

    fn new(kind: DevSkillAuthoringErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }
}

impl fmt::Display for DevSkillAuthoringError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for DevSkillAuthoringError {}

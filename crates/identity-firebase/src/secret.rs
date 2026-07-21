use std::fmt;
use zeroize::Zeroizing;

pub struct FirebaseSecret(Zeroizing<String>);

impl FirebaseSecret {
    pub fn new(value: impl Into<String>) -> Self {
        Self(Zeroizing::new(value.into()))
    }

    pub fn expose_secret(&self) -> &str {
        self.0.as_str()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl Clone for FirebaseSecret {
    fn clone(&self) -> Self {
        Self::new(self.expose_secret())
    }
}

impl fmt::Debug for FirebaseSecret {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("FirebaseSecret([REDACTED])")
    }
}

impl<'de> serde::Deserialize<'de> for FirebaseSecret {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        <String as serde::Deserialize>::deserialize(deserializer).map(Self::new)
    }
}

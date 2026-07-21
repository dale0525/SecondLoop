const OFFICIAL_FIREBASE_OAUTH_CLIENT_ID: &str =
    "11389499001-bib8sttfdcudgcodohveg2o2kthq4qrq.apps.googleusercontent.com";
// Google requires this value for Desktop token exchange. Installed-app client
// secrets are non-confidential metadata, matching Firebase CLI's public client.
const OFFICIAL_FIREBASE_OAUTH_CLIENT_SECRET: &str = "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";

#[derive(Clone, Debug, Default)]
pub(crate) struct FirebaseOAuthDefaults {
    pub(crate) client_id: Option<String>,
    pub(crate) client_secret: Option<String>,
}

impl FirebaseOAuthDefaults {
    pub(crate) fn official() -> Self {
        Self {
            client_id: Some(OFFICIAL_FIREBASE_OAUTH_CLIENT_ID.into()),
            client_secret: Some(OFFICIAL_FIREBASE_OAUTH_CLIENT_SECRET.into()),
        }
    }

    pub(crate) fn from_environment() -> anyhow::Result<Self> {
        Self::with_overrides(
            environment_override("AGENTWEAVE_FIREBASE_OAUTH_CLIENT_ID")?,
            environment_override("AGENTWEAVE_FIREBASE_OAUTH_CLIENT_SECRET")?,
        )
    }

    pub(crate) fn public_client_available(&self) -> bool {
        self.client_id.is_some()
    }

    fn with_overrides(
        client_id: Option<String>,
        client_secret: Option<String>,
    ) -> anyhow::Result<Self> {
        let client_id = client_id.filter(|value| !value.trim().is_empty());
        let client_secret = client_secret.filter(|value| !value.trim().is_empty());
        if client_id.is_none() && client_secret.is_none() {
            return Ok(Self::official());
        }
        if client_id.is_none() && client_secret.is_some() {
            anyhow::bail!("Firebase OAuth client secret requires a client ID");
        }
        for value in [client_id.as_deref(), client_secret.as_deref()]
            .into_iter()
            .flatten()
        {
            anyhow::ensure!(
                value.len() <= 4096 && !value.chars().any(char::is_control),
                "Firebase OAuth client configuration is invalid"
            );
        }
        Ok(Self {
            client_id,
            client_secret,
        })
    }
}

fn environment_override(name: &str) -> anyhow::Result<Option<String>> {
    match std::env::var(name) {
        Ok(value) => Ok(Some(value)),
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(std::env::VarError::NotUnicode(_)) => {
            anyhow::bail!("{name} must contain valid Unicode")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn official_desktop_client_contains_required_public_metadata() {
        let defaults = FirebaseOAuthDefaults::official();

        assert_eq!(
            defaults.client_id.as_deref(),
            Some(OFFICIAL_FIREBASE_OAUTH_CLIENT_ID)
        );
        assert_eq!(
            defaults.client_secret.as_deref(),
            Some(OFFICIAL_FIREBASE_OAUTH_CLIENT_SECRET)
        );
        assert!(defaults.public_client_available());
    }

    #[test]
    fn empty_overrides_fall_back_to_the_official_client() {
        for defaults in [
            FirebaseOAuthDefaults::with_overrides(None, None).unwrap(),
            FirebaseOAuthDefaults::with_overrides(Some(" \t".into()), None).unwrap(),
            FirebaseOAuthDefaults::with_overrides(None, Some(" \n".into())).unwrap(),
            FirebaseOAuthDefaults::with_overrides(Some(" ".into()), Some("\t".into())).unwrap(),
        ] {
            assert_eq!(
                defaults.client_id.as_deref(),
                Some(OFFICIAL_FIREBASE_OAUTH_CLIENT_ID)
            );
            assert_eq!(
                defaults.client_secret.as_deref(),
                Some(OFFICIAL_FIREBASE_OAUTH_CLIENT_SECRET)
            );
        }
    }

    #[test]
    fn downstream_can_override_the_official_client() {
        let public_client =
            FirebaseOAuthDefaults::with_overrides(Some("downstream-client".into()), None).unwrap();
        assert_eq!(
            public_client.client_id.as_deref(),
            Some("downstream-client")
        );
        assert_eq!(public_client.client_secret, None);

        let confidential_client = FirebaseOAuthDefaults::with_overrides(
            Some("downstream-client".into()),
            Some("downstream-secret".into()),
        )
        .unwrap();
        assert_eq!(
            confidential_client.client_id.as_deref(),
            Some("downstream-client")
        );
        assert_eq!(
            confidential_client.client_secret.as_deref(),
            Some("downstream-secret")
        );
    }

    #[test]
    fn secret_only_override_is_rejected() {
        assert!(
            FirebaseOAuthDefaults::with_overrides(None, Some("downstream-secret".into())).is_err()
        );
        assert!(
            FirebaseOAuthDefaults::with_overrides(
                Some(" \t".into()),
                Some("downstream-secret".into())
            )
            .is_err()
        );
    }
}

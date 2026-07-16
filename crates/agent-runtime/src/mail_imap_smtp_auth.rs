use super::ImapSmtpMailConnector;
use crate::mail::{MailError, MailResult};
use async_imap::Authenticator;
use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MailAuthentication {
    #[default]
    Password,
    XOAuth2,
}

pub(super) struct XOAuth2Authenticator<'a> {
    pub(super) username: &'a str,
    pub(super) token: &'a str,
}

impl Authenticator for &XOAuth2Authenticator<'_> {
    type Response = String;

    fn process(&mut self, _: &[u8]) -> Self::Response {
        format!(
            "user={}\x01auth=Bearer {}\x01\x01",
            self.username, self.token
        )
    }
}

impl ImapSmtpMailConnector {
    pub(super) async fn credential(&self, scopes: &[&str]) -> MailResult<String> {
        let required = self
            .credential_scopes
            .clone()
            .unwrap_or_else(|| scopes.iter().map(|scope| (*scope).to_string()).collect());
        let material = self
            .vault
            .lease_for_connector(
                &self.config.credential_scope,
                &self.credential_connector_id,
                &self.config.account.id,
                &required,
            )
            .await
            .map_err(super::redacted_connector_error)?;
        std::str::from_utf8(material.expose_bytes())
            .map(str::to_owned)
            .map_err(|_| MailError::Connector("credential is not valid UTF-8".into()))
    }

    pub fn with_xoauth2_authentication(
        mut self,
        connector_id: impl Into<String>,
        credential_scopes: BTreeSet<String>,
    ) -> anyhow::Result<Self> {
        anyhow::ensure!(
            !credential_scopes.is_empty(),
            "XOAUTH2 credential scopes are required"
        );
        self.authentication = MailAuthentication::XOAuth2;
        self.credential_connector_id = connector_id.into();
        self.credential_scopes = Some(credential_scopes);
        Ok(self)
    }
}

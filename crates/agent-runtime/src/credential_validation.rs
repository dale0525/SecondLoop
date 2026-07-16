use super::{ConnectorAccount, ProviderCredential};

pub(super) fn validate_connector_account(account: &ConnectorAccount) -> anyhow::Result<()> {
    account.scope.validate()?;
    for value in [
        &account.account_id,
        &account.connector_id,
        &account.credential_id,
    ] {
        anyhow::ensure!(
            !value.trim().is_empty(),
            "connector account field is required"
        );
        anyhow::ensure!(value.len() <= 255, "connector account field is too long");
    }
    Ok(())
}

pub(super) fn validate_provider_credential(credential: &ProviderCredential) -> anyhow::Result<()> {
    for value in [
        &credential.credential_id,
        &credential.provider_id,
        &credential.provider_subject,
    ] {
        anyhow::ensure!(
            !value.trim().is_empty(),
            "provider credential field is required"
        );
        anyhow::ensure!(value.len() <= 255, "provider credential field is too long");
    }
    anyhow::ensure!(
        credential.refresh_secret_id.as_ref() != Some(&credential.access_secret_id),
        "access and refresh secret IDs must differ"
    );
    Ok(())
}

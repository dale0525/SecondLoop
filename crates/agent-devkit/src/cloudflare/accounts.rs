use super::{CLOUDFLARE_PROVIDER_ID, provider_support::validate_cloudflare_segment};
use crate::{DeveloperAccount, DevkitError, DevkitErrorCode, DevkitResult};
use serde_json::Value;
use std::collections::BTreeSet;

const MAX_ACCOUNTS: usize = 10_000;

pub(super) fn parse_cloudflare_accounts(value: &Value) -> DevkitResult<Vec<DeveloperAccount>> {
    let records = value.as_array().ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare account list has an invalid shape",
        )
    })?;
    if records.len() > MAX_ACCOUNTS {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare account list exceeds the size limit",
        ));
    }
    let mut ids = BTreeSet::new();
    let mut accounts = Vec::with_capacity(records.len());
    for record in records {
        let object = record.as_object().ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare account list contains an invalid record",
            )
        })?;
        let account_id = object.get("id").and_then(Value::as_str).ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare account record omitted its id",
            )
        })?;
        validate_cloudflare_segment("account id", account_id)?;
        if !ids.insert(account_id.to_owned()) {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare account list contains a duplicate id",
            ));
        }
        let display_name = match object.get("name") {
            None | Some(Value::Null) => None,
            Some(Value::String(name)) if name.trim().is_empty() => None,
            Some(Value::String(name)) => Some(name.clone()),
            Some(_) => {
                return Err(DevkitError::new(
                    DevkitErrorCode::RemoteProtocol,
                    "Cloudflare account record has an invalid display name",
                ));
            }
        };
        let account = DeveloperAccount {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            account_id: account_id.into(),
            display_name,
        };
        account.validate()?;
        accounts.push(account);
    }
    accounts.sort_by(|left, right| left.account_id.cmp(&right.account_id));
    Ok(accounts)
}

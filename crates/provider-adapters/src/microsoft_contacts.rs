use crate::credential_source::ProviderCredentialSource;
use crate::http::{ProviderHttpClient, ProviderHttpRequest, ProviderHttpResponse};
use agent_runtime::contacts::{
    ApprovedContactMutation, ContactIdentity, ContactMutationPreview, ContactRecord, ContactScope,
    ContactsConnector,
};
use agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use reqwest::{Method, Url};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const CONTACTS_SCOPE: &str = "Contacts.ReadWrite";
const MAX_CONTACT_PAGES: usize = 20;

pub struct MicrosoftContactsConnector {
    http: Arc<dyn ProviderHttpClient>,
    credentials: Arc<dyn ProviderCredentialSource>,
    state: Mutex<MicrosoftContactsState>,
}

#[derive(Default)]
struct MicrosoftContactsState {
    previews: BTreeMap<String, (ContactScope, ContactMutationPreview)>,
    results: BTreeMap<(ContactScope, String), ContactRecord>,
}

impl MicrosoftContactsConnector {
    pub fn new(
        http: Arc<dyn ProviderHttpClient>,
        credentials: Arc<dyn ProviderCredentialSource>,
    ) -> Self {
        Self {
            http,
            credentials,
            state: Mutex::new(MicrosoftContactsState::default()),
        }
    }

    async fn execute(
        &self,
        scope: &ContactScope,
        request: ProviderHttpRequest,
    ) -> anyhow::Result<ProviderHttpResponse> {
        let token = self
            .credentials
            .access_token(
                CONTACTS_CONNECTOR_ID,
                &scope.account_id,
                &BTreeSet::from([CONTACTS_SCOPE.into()]),
            )
            .await?;
        self.http.execute(request, &token).await
    }

    async fn graph_contact(
        &self,
        scope: &ContactScope,
        contact_id: &str,
    ) -> anyhow::Result<Option<GraphContact>> {
        let response = self
            .execute(
                scope,
                ProviderHttpRequest::get(format!("/v1.0/me/contacts/{}", segment(contact_id))),
            )
            .await?;
        if response.status == 404 {
            return Ok(None);
        }
        response.json().map(Some)
    }

    async fn all_contacts(&self, scope: &ContactScope) -> anyhow::Result<Vec<GraphContact>> {
        let mut request = ProviderHttpRequest::get("/v1.0/me/contacts");
        request.query = vec![("$top".into(), "999".into())];
        let mut contacts = Vec::new();
        for _ in 0..MAX_CONTACT_PAGES {
            let page: GraphContactPage = self.execute(scope, request).await?.json()?;
            contacts.extend(page.value);
            let Some(next_link) = page.next_link else {
                return Ok(contacts);
            };
            request = next_page_request(&next_link)?;
        }
        anyhow::bail!("Microsoft Contacts result exceeds pagination limit")
    }
}

#[async_trait]
impl ContactsConnector for MicrosoftContactsConnector {
    async fn resolve(
        &self,
        scope: &ContactScope,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<ContactRecord>> {
        anyhow::ensure!(
            !query.trim().is_empty() && query.len() <= 1024,
            "contact query is invalid"
        );
        anyhow::ensure!((1..=50).contains(&limit), "contact result limit is invalid");
        let query = query.to_lowercase();
        let mut contacts = self
            .all_contacts(scope)
            .await?
            .into_iter()
            .map(normalize_contact)
            .collect::<anyhow::Result<Vec<_>>>()?;
        contacts.retain(|contact| {
            contact.display_name.to_lowercase().contains(&query)
                || contact
                    .identities
                    .iter()
                    .any(|identity| identity.value.to_lowercase().contains(&query))
        });
        contacts.sort_by(|left, right| {
            left.display_name
                .cmp(&right.display_name)
                .then_with(|| left.id.cmp(&right.id))
        });
        contacts.truncate(limit);
        Ok(contacts)
    }

    async fn get(
        &self,
        scope: &ContactScope,
        contact_id: &str,
    ) -> anyhow::Result<Option<ContactRecord>> {
        self.graph_contact(scope, contact_id)
            .await?
            .map(normalize_contact)
            .transpose()
    }

    async fn preview_update(
        &self,
        scope: &ContactScope,
        contact_id: &str,
        expected_version: u64,
        mut replacement: ContactRecord,
        idempotency_key: String,
    ) -> anyhow::Result<ContactMutationPreview> {
        anyhow::ensure!(
            !idempotency_key.trim().is_empty(),
            "idempotency key is required"
        );
        let current = self
            .get(scope, contact_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Microsoft contact not found"))?;
        anyhow::ensure!(
            current.version == expected_version,
            "Microsoft contact version conflict"
        );
        replacement.id = current.id.clone();
        replacement.provider_id = current.provider_id.clone();
        replacement.version = expected_version + 1;
        replacement.updated_at = current.updated_at;
        replacement.validate()?;
        let preview_hash = hex::encode(Sha256::digest(serde_json::to_vec(&(
            scope,
            contact_id,
            expected_version,
            &replacement,
            &idempotency_key,
        ))?));
        let mut state = self
            .state
            .lock()
            .expect("Microsoft Contacts state poisoned");
        if let Some((_, existing)) = state.previews.values().find(|(existing_scope, existing)| {
            existing_scope == scope && existing.idempotency_key == idempotency_key
        }) {
            anyhow::ensure!(
                existing.preview_hash == preview_hash,
                "Microsoft Contacts idempotency conflict"
            );
            return Ok(existing.clone());
        }
        let preview = ContactMutationPreview {
            preview_id: Uuid::new_v4().to_string(),
            account_id: scope.account_id.clone(),
            contact_id: current.id,
            expected_version,
            replacement,
            preview_hash,
            idempotency_key,
        };
        preview.validate()?;
        state
            .previews
            .insert(preview.preview_id.clone(), (scope.clone(), preview.clone()));
        Ok(preview)
    }

    async fn apply(
        &self,
        scope: &ContactScope,
        approval: ApprovedContactMutation,
    ) -> anyhow::Result<ContactRecord> {
        anyhow::ensure!(
            !approval.approval_id.trim().is_empty(),
            "approval is required"
        );
        let preview = {
            let state = self
                .state
                .lock()
                .expect("Microsoft Contacts state poisoned");
            let (preview_scope, preview) = state
                .previews
                .get(&approval.preview_id)
                .ok_or_else(|| anyhow::anyhow!("Microsoft Contacts preview not found"))?;
            anyhow::ensure!(
                preview_scope == scope && preview.preview_hash == approval.preview_hash,
                "Microsoft Contacts approval does not match preview"
            );
            if let Some(result) = state
                .results
                .get(&(scope.clone(), preview.idempotency_key.clone()))
            {
                return Ok(result.clone());
            }
            preview.clone()
        };
        let provider_id = preview
            .replacement
            .provider_id
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("Microsoft Contacts provider id is missing"))?;
        anyhow::ensure!(
            provider_id == preview.contact_id,
            "Microsoft Contacts provider id does not match the approved contact"
        );
        let current = self
            .graph_contact(scope, provider_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Microsoft contact not found"))?;
        anyhow::ensure!(
            contact_version(&current)? == preview.expected_version,
            "Microsoft contact version conflict"
        );
        let mut request = ProviderHttpRequest::json(
            Method::PATCH,
            format!("/v1.0/me/contacts/{}", segment(provider_id)),
            contact_body(&preview.replacement)?,
        );
        let etag = current
            .etag
            .as_deref()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| anyhow::anyhow!("Microsoft contact etag is missing"))?;
        request.headers.insert("If-Match".into(), etag.into());
        let mut result = normalize_contact(self.execute(scope, request).await?.json()?)?;
        result.updated_at = Utc::now();
        self.state
            .lock()
            .expect("Microsoft Contacts state poisoned")
            .results
            .insert((scope.clone(), preview.idempotency_key), result.clone());
        Ok(result)
    }
}

#[derive(Deserialize)]
struct GraphContactPage {
    #[serde(default)]
    value: Vec<GraphContact>,
    #[serde(rename = "@odata.nextLink")]
    next_link: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GraphContact {
    id: String,
    #[serde(rename = "@odata.etag")]
    etag: Option<String>,
    change_key: Option<String>,
    display_name: String,
    #[serde(default)]
    email_addresses: Vec<GraphEmailAddress>,
    #[serde(default)]
    business_phones: Vec<String>,
    #[serde(default)]
    home_phones: Vec<String>,
    mobile_phone: Option<String>,
    company_name: Option<String>,
    last_modified_date_time: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
struct GraphEmailAddress {
    address: String,
}

fn normalize_contact(contact: GraphContact) -> anyhow::Result<ContactRecord> {
    let version = contact_version(&contact)?;
    let identities = contact
        .email_addresses
        .into_iter()
        .map(|email| ContactIdentity {
            kind: "email".into(),
            value: email.address,
            label: None,
        })
        .chain(
            contact
                .business_phones
                .into_iter()
                .map(|value| ContactIdentity {
                    kind: "phone".into(),
                    value,
                    label: Some("business".into()),
                }),
        )
        .chain(
            contact
                .home_phones
                .into_iter()
                .map(|value| ContactIdentity {
                    kind: "phone".into(),
                    value,
                    label: Some("home".into()),
                }),
        )
        .chain(
            contact
                .mobile_phone
                .into_iter()
                .map(|value| ContactIdentity {
                    kind: "phone".into(),
                    value,
                    label: Some("mobile".into()),
                }),
        )
        .collect();
    let record = ContactRecord {
        id: contact.id.clone(),
        display_name: contact.display_name,
        identities,
        organization: contact.company_name.filter(|value| !value.is_empty()),
        relationship: None,
        version,
        provider_id: Some(contact.id),
        updated_at: contact.last_modified_date_time.unwrap_or_else(Utc::now),
    };
    record.validate()?;
    Ok(record)
}

fn contact_body(contact: &ContactRecord) -> anyhow::Result<Value> {
    contact.validate()?;
    let emails = contact
        .identities
        .iter()
        .filter(|identity| identity.kind == "email")
        .map(|identity| json!({"address": identity.value, "name": contact.display_name}))
        .collect::<Vec<_>>();
    let mut business_phones = Vec::new();
    let mut home_phones = Vec::new();
    let mut mobile_phone = None;
    for identity in contact
        .identities
        .iter()
        .filter(|identity| identity.kind == "phone")
    {
        match identity
            .label
            .as_deref()
            .map(str::to_ascii_lowercase)
            .as_deref()
        {
            Some("home") => home_phones.push(identity.value.clone()),
            Some("mobile") => {
                anyhow::ensure!(
                    mobile_phone.is_none(),
                    "Microsoft contact supports only one mobile phone"
                );
                mobile_phone = Some(identity.value.clone());
            }
            _ => business_phones.push(identity.value.clone()),
        }
    }
    Ok(json!({
        "displayName": contact.display_name,
        "emailAddresses": emails,
        "businessPhones": business_phones,
        "homePhones": home_phones,
        "mobilePhone": mobile_phone,
        "companyName": contact.organization,
    }))
}

fn contact_version(contact: &GraphContact) -> anyhow::Result<u64> {
    let source = contact
        .change_key
        .as_deref()
        .or(contact.etag.as_deref())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("Microsoft contact version is missing"))?;
    Ok(version_hash(source))
}

fn version_hash(value: &str) -> u64 {
    let digest = Sha256::digest(value.as_bytes());
    u64::from_be_bytes(digest[..8].try_into().expect("SHA-256 prefix")) | 1
}

fn next_page_request(next_link: &str) -> anyhow::Result<ProviderHttpRequest> {
    let url = Url::parse(next_link)?;
    anyhow::ensure!(
        url.scheme() == "https" && url.host_str() == Some("graph.microsoft.com"),
        "Microsoft Contacts pagination escaped the Graph origin"
    );
    anyhow::ensure!(
        url.path() == "/v1.0/me/contacts",
        "Microsoft Contacts pagination path is invalid"
    );
    let mut request = ProviderHttpRequest::get(url.path());
    request.query = url
        .query_pairs()
        .map(|(name, value)| (name.into_owned(), value.into_owned()))
        .collect();
    Ok(request)
}

fn segment(value: &str) -> String {
    utf8_percent_encode(value, NON_ALPHANUMERIC).to_string()
}

#[cfg(test)]
#[path = "microsoft_contacts_tests.rs"]
mod tests;

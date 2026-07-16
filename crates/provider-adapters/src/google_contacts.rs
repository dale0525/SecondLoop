use crate::credential_source::ProviderCredentialSource;
use crate::http::{ProviderHttpClient, ProviderHttpRequest};
use agent_runtime::contacts::{
    ApprovedContactMutation, ContactIdentity, ContactMutationPreview, ContactRecord, ContactScope,
    ContactsConnector,
};
use agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID;
use async_trait::async_trait;
use chrono::Utc;
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use reqwest::Method;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const CONTACTS_SCOPE: &str = "https://www.googleapis.com/auth/contacts";
const READ_MASK: &str = "names,emailAddresses,phoneNumbers,organizations,metadata";

pub struct GoogleContactsConnector {
    http: Arc<dyn ProviderHttpClient>,
    credentials: Arc<dyn ProviderCredentialSource>,
    state: Mutex<GoogleContactsState>,
}

#[derive(Default)]
struct GoogleContactsState {
    previews: BTreeMap<String, (ContactScope, ContactMutationPreview)>,
    results: BTreeMap<(ContactScope, String), ContactRecord>,
}

impl GoogleContactsConnector {
    pub fn new(
        http: Arc<dyn ProviderHttpClient>,
        credentials: Arc<dyn ProviderCredentialSource>,
    ) -> Self {
        Self {
            http,
            credentials,
            state: Mutex::new(GoogleContactsState::default()),
        }
    }

    async fn execute(
        &self,
        scope: &ContactScope,
        request: ProviderHttpRequest,
    ) -> anyhow::Result<crate::http::ProviderHttpResponse> {
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

    async fn get_person(
        &self,
        scope: &ContactScope,
        contact_id: &str,
    ) -> anyhow::Result<Option<GooglePerson>> {
        let path = person_path(contact_id)?;
        let mut request = ProviderHttpRequest::get(format!("/v1/{path}"));
        request
            .query
            .push(("personFields".into(), READ_MASK.into()));
        let response = self.execute(scope, request).await?;
        if response.status == 404 {
            return Ok(None);
        }
        response.json().map(Some)
    }
}

#[async_trait]
impl ContactsConnector for GoogleContactsConnector {
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
        let mut request = ProviderHttpRequest::get("/v1/people:searchContacts");
        request.query = vec![
            ("query".into(), query.into()),
            ("readMask".into(), READ_MASK.into()),
            ("pageSize".into(), limit.to_string()),
        ];
        let response: SearchContactsResponse = self.execute(scope, request).await?.json()?;
        let mut contacts = response
            .results
            .into_iter()
            .map(|result| normalize_person(result.person))
            .collect::<anyhow::Result<Vec<_>>>()?;
        contacts.truncate(limit);
        Ok(contacts)
    }

    async fn get(
        &self,
        scope: &ContactScope,
        contact_id: &str,
    ) -> anyhow::Result<Option<ContactRecord>> {
        self.get_person(scope, contact_id)
            .await?
            .map(normalize_person)
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
        let current = self
            .get(scope, contact_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Google contact not found"))?;
        anyhow::ensure!(
            current.version == expected_version,
            "Google contact version conflict"
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
        let mut state = self.state.lock().expect("Google Contacts state poisoned");
        if let Some((_, existing)) = state.previews.values().find(|(existing_scope, existing)| {
            existing_scope == scope && existing.idempotency_key == idempotency_key
        }) {
            anyhow::ensure!(
                existing.preview_hash == preview_hash,
                "Google Contacts idempotency conflict"
            );
            return Ok(existing.clone());
        }
        let preview = ContactMutationPreview {
            preview_id: Uuid::new_v4().to_string(),
            account_id: scope.account_id.clone(),
            contact_id: contact_id.into(),
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
            let state = self.state.lock().expect("Google Contacts state poisoned");
            let (preview_scope, preview) = state
                .previews
                .get(&approval.preview_id)
                .ok_or_else(|| anyhow::anyhow!("Google Contacts preview not found"))?;
            anyhow::ensure!(
                preview_scope == scope && preview.preview_hash == approval.preview_hash,
                "Google Contacts approval does not match preview"
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
            .ok_or_else(|| anyhow::anyhow!("Google Contacts provider id is missing"))?;
        let path = person_path(provider_id)?;
        let current = self
            .get_person(scope, &preview.contact_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Google contact not found"))?;
        anyhow::ensure!(
            etag_version(&current.etag) == preview.expected_version,
            "Google contact version conflict"
        );
        let mut request = ProviderHttpRequest::json(
            Method::PATCH,
            format!("/v1/{path}:updateContact"),
            person_body(&preview.replacement, &current.resource_name, &current.etag),
        );
        request.query.push((
            "updatePersonFields".into(),
            "names,emailAddresses,phoneNumbers,organizations".into(),
        ));
        request
            .query
            .push(("personFields".into(), READ_MASK.into()));
        let mut result = normalize_person(self.execute(scope, request).await?.json()?)?;
        result.updated_at = Utc::now();
        self.state
            .lock()
            .expect("Google Contacts state poisoned")
            .results
            .insert((scope.clone(), preview.idempotency_key), result.clone());
        Ok(result)
    }
}

#[derive(Deserialize)]
struct SearchContactsResponse {
    #[serde(default)]
    results: Vec<SearchResult>,
}

#[derive(Deserialize)]
struct SearchResult {
    person: GooglePerson,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GooglePerson {
    resource_name: String,
    etag: String,
    #[serde(default)]
    names: Vec<GoogleName>,
    #[serde(default)]
    email_addresses: Vec<GoogleValue>,
    #[serde(default)]
    phone_numbers: Vec<GoogleValue>,
    #[serde(default)]
    organizations: Vec<GoogleOrganization>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleName {
    display_name: Option<String>,
}

#[derive(Deserialize)]
struct GoogleValue {
    value: String,
    #[serde(rename = "type")]
    kind: Option<String>,
}

#[derive(Deserialize)]
struct GoogleOrganization {
    name: Option<String>,
}

fn normalize_person(person: GooglePerson) -> anyhow::Result<ContactRecord> {
    let display_name = person
        .names
        .iter()
        .find_map(|name| name.display_name.clone())
        .ok_or_else(|| anyhow::anyhow!("Google contact display name is missing"))?;
    let identities = person
        .email_addresses
        .into_iter()
        .map(|value| ContactIdentity {
            kind: "email".into(),
            value: value.value,
            label: value.kind,
        })
        .chain(
            person
                .phone_numbers
                .into_iter()
                .map(|value| ContactIdentity {
                    kind: "phone".into(),
                    value: value.value,
                    label: value.kind,
                }),
        )
        .collect();
    let contact = ContactRecord {
        id: person.resource_name.clone(),
        display_name,
        identities,
        organization: person
            .organizations
            .into_iter()
            .find_map(|value| value.name),
        relationship: None,
        version: etag_version(&person.etag),
        provider_id: Some(person.resource_name),
        updated_at: Utc::now(),
    };
    contact.validate()?;
    Ok(contact)
}

fn person_body(contact: &ContactRecord, resource_name: &str, etag: &str) -> Value {
    let emails = contact
        .identities
        .iter()
        .filter(|identity| identity.kind == "email")
        .map(|identity| json!({"value": identity.value, "type": identity.label}))
        .collect::<Vec<_>>();
    let phones = contact
        .identities
        .iter()
        .filter(|identity| identity.kind == "phone")
        .map(|identity| json!({"value": identity.value, "type": identity.label}))
        .collect::<Vec<_>>();
    json!({
        "resourceName": resource_name,
        "etag": etag,
        "names": [{"displayName": contact.display_name, "unstructuredName": contact.display_name}],
        "emailAddresses": emails,
        "phoneNumbers": phones,
        "organizations": contact.organization.as_ref().map(|name| vec![json!({"name": name})]).unwrap_or_default(),
    })
}

fn person_path(value: &str) -> anyhow::Result<String> {
    let mut parts = value.split('/');
    anyhow::ensure!(
        parts.next() == Some("people"),
        "Google contact resource name is invalid"
    );
    let id = parts.next().unwrap_or_default();
    anyhow::ensure!(
        !id.is_empty() && parts.next().is_none(),
        "Google contact resource name is invalid"
    );
    Ok(format!(
        "people/{}",
        utf8_percent_encode(id, NON_ALPHANUMERIC)
    ))
}

fn etag_version(etag: &str) -> u64 {
    let digest = Sha256::digest(etag.as_bytes());
    u64::from_be_bytes(digest[..8].try_into().expect("SHA-256 prefix")) | 1
}

#[cfg(test)]
#[path = "google_contacts_tests.rs"]
mod tests;

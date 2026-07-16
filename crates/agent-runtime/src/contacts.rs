use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContactScope {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
    pub account_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContactIdentity {
    pub kind: String,
    pub value: String,
    pub label: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContactRecord {
    pub id: String,
    pub display_name: String,
    pub identities: Vec<ContactIdentity>,
    pub organization: Option<String>,
    pub relationship: Option<String>,
    pub version: u64,
    pub provider_id: Option<String>,
    pub updated_at: DateTime<Utc>,
}

impl ContactRecord {
    pub fn validate(&self) -> anyhow::Result<()> {
        validate_text(&self.id, 512, "contact id")?;
        validate_text(&self.display_name, 1024, "contact display name")?;
        anyhow::ensure!(self.version > 0, "contact version is invalid");
        anyhow::ensure!(!self.identities.is_empty(), "contact identity is required");
        anyhow::ensure!(
            self.identities.len() <= 100,
            "contact has too many identities"
        );
        if let Some(value) = &self.organization {
            validate_text(value, 2048, "contact organization")?;
        }
        if let Some(value) = &self.relationship {
            validate_text(value, 2048, "contact relationship")?;
        }
        if let Some(value) = &self.provider_id {
            validate_text(value, 512, "contact provider id")?;
        }
        for identity in &self.identities {
            validate_text(&identity.kind, 64, "contact identity kind")?;
            validate_text(&identity.value, 2048, "contact identity value")?;
            if let Some(label) = &identity.label {
                validate_text(label, 255, "contact identity label")?;
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContactMutationPreview {
    pub preview_id: String,
    pub account_id: String,
    pub contact_id: String,
    pub expected_version: u64,
    pub replacement: ContactRecord,
    pub preview_hash: String,
    pub idempotency_key: String,
}

impl ContactMutationPreview {
    pub fn validate(&self) -> anyhow::Result<()> {
        validate_text(&self.preview_id, 512, "contact preview id")?;
        validate_text(&self.account_id, 255, "contact account id")?;
        validate_text(&self.contact_id, 512, "contact id")?;
        anyhow::ensure!(
            self.expected_version > 0,
            "contact expected version is invalid"
        );
        anyhow::ensure!(
            self.replacement.id == self.contact_id
                && self.replacement.version == self.expected_version + 1,
            "contact replacement version binding is invalid"
        );
        self.replacement.validate()?;
        validate_sha256(&self.preview_hash, "contact preview hash")?;
        validate_text(&self.idempotency_key, 512, "contact idempotency key")?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApprovedContactMutation {
    pub preview_id: String,
    pub preview_hash: String,
    pub approval_id: String,
}

#[async_trait]
pub trait ContactsConnector: Send + Sync {
    async fn resolve(
        &self,
        scope: &ContactScope,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<ContactRecord>>;
    async fn get(
        &self,
        scope: &ContactScope,
        contact_id: &str,
    ) -> anyhow::Result<Option<ContactRecord>>;
    async fn preview_update(
        &self,
        scope: &ContactScope,
        contact_id: &str,
        expected_version: u64,
        replacement: ContactRecord,
        idempotency_key: String,
    ) -> anyhow::Result<ContactMutationPreview>;
    async fn apply(
        &self,
        scope: &ContactScope,
        approval: ApprovedContactMutation,
    ) -> anyhow::Result<ContactRecord>;
}

#[derive(Clone, Default)]
pub struct FakeContactsConnector {
    state: Arc<Mutex<FakeContactsState>>,
}

#[derive(Default)]
struct FakeContactsState {
    contacts: BTreeMap<(ContactScope, String), ContactRecord>,
    previews: HashMap<String, (ContactScope, ContactMutationPreview)>,
    results: BTreeMap<(ContactScope, String), ContactRecord>,
}

impl FakeContactsConnector {
    pub fn seed(&self, scope: ContactScope, contact: ContactRecord) -> anyhow::Result<()> {
        contact.validate()?;
        self.state
            .lock()
            .expect("contacts lock poisoned")
            .contacts
            .insert((scope, contact.id.clone()), contact);
        Ok(())
    }
}

#[async_trait]
impl ContactsConnector for FakeContactsConnector {
    async fn resolve(
        &self,
        scope: &ContactScope,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<ContactRecord>> {
        validate_text(query, 1024, "contact query")?;
        anyhow::ensure!((1..=50).contains(&limit), "contact result limit is invalid");
        let query = query.to_lowercase();
        let mut contacts = self
            .state
            .lock()
            .expect("contacts lock poisoned")
            .contacts
            .iter()
            .filter(|((contact_scope, _), contact)| {
                contact_scope == scope
                    && (contact.display_name.to_lowercase().contains(&query)
                        || contact
                            .identities
                            .iter()
                            .any(|identity| identity.value.to_lowercase().contains(&query)))
            })
            .map(|(_, contact)| contact.clone())
            .collect::<Vec<_>>();
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
        validate_text(contact_id, 512, "contact id")?;
        Ok(self
            .state
            .lock()
            .expect("contacts lock poisoned")
            .contacts
            .get(&(scope.clone(), contact_id.to_string()))
            .cloned())
    }

    async fn preview_update(
        &self,
        scope: &ContactScope,
        contact_id: &str,
        expected_version: u64,
        mut replacement: ContactRecord,
        idempotency_key: String,
    ) -> anyhow::Result<ContactMutationPreview> {
        validate_text(contact_id, 512, "contact id")?;
        validate_text(&idempotency_key, 512, "contact idempotency key")?;
        let mut state = self.state.lock().expect("contacts lock poisoned");
        let current = state
            .contacts
            .get(&(scope.clone(), contact_id.into()))
            .ok_or_else(|| anyhow::anyhow!("contact not found"))?;
        anyhow::ensure!(
            current.version == expected_version,
            "contact version conflict"
        );
        replacement.id = contact_id.into();
        replacement.version = expected_version + 1;
        replacement.provider_id = current.provider_id.clone();
        replacement.updated_at = current.updated_at;
        replacement.validate()?;
        let preview_hash = hex::encode(Sha256::digest(serde_json::to_vec(&(
            scope,
            contact_id,
            expected_version,
            &replacement,
            &idempotency_key,
        ))?));
        if let Some((_, existing)) = state.previews.values().find(|(existing_scope, existing)| {
            existing_scope == scope && existing.idempotency_key == idempotency_key
        }) {
            anyhow::ensure!(
                existing.preview_hash == preview_hash,
                "contact idempotency key conflicts with another preview"
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
        validate_text(&approval.approval_id, 512, "contact approval id")?;
        let mut state = self.state.lock().expect("contacts lock poisoned");
        let (preview_scope, preview) = state
            .previews
            .get(&approval.preview_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("contact preview not found"))?;
        anyhow::ensure!(
            &preview_scope == scope && approval.preview_hash == preview.preview_hash,
            "contact approval does not match preview"
        );
        let result_key = (scope.clone(), preview.idempotency_key.clone());
        if let Some(existing) = state.results.get(&result_key) {
            return Ok(existing.clone());
        }
        let current = state
            .contacts
            .get(&(scope.clone(), preview.contact_id.clone()))
            .ok_or_else(|| anyhow::anyhow!("contact not found"))?;
        anyhow::ensure!(
            current.version == preview.expected_version,
            "contact version conflict"
        );
        let mut replacement = preview.replacement;
        replacement.updated_at = Utc::now();
        state
            .contacts
            .insert((scope.clone(), replacement.id.clone()), replacement.clone());
        state.results.insert(result_key, replacement.clone());
        Ok(replacement)
    }
}

fn validate_text(value: &str, max: usize, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.trim().is_empty(), "{name} is required");
    anyhow::ensure!(value.len() <= max, "{name} is too long");
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{name} contains control characters"
    );
    Ok(())
}

fn validate_sha256(value: &str, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "{name} is invalid"
    );
    Ok(())
}

#[cfg(test)]
#[path = "contacts_tests.rs"]
mod tests;

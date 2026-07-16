use crate::approval::immutable_arguments_hash;
use crate::contacts::ContactMutationPreview;
use crate::contacts_connector_transport::CONTACTS_CONNECTOR_ID;
use crate::foundation_action_envelope::{
    FoundationActionEffect, FoundationActionEnvelope, FoundationActionPreview,
    FoundationActionResource,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const CONTACTS_ACTION_ENVELOPE_VERSION: u32 = 1;
pub const CONTACT_UPDATE_ACTION_KIND: &str = "contacts.contact.update";
pub const CONTACT_UPDATE_OPERATION: &str = "contact_update_apply";

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CanonicalContactActionEnvelope {
    pub schema_version: u32,
    pub preview: ContactMutationPreview,
    pub preview_sha256: String,
}

impl CanonicalContactActionEnvelope {
    pub fn from_preview(preview: ContactMutationPreview) -> anyhow::Result<Self> {
        let preview_sha256 = immutable_arguments_hash(&serde_json::to_value(&preview)?)?;
        let action = Self {
            schema_version: CONTACTS_ACTION_ENVELOPE_VERSION,
            preview,
            preview_sha256,
        };
        action.validate()?;
        Ok(action)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.schema_version == CONTACTS_ACTION_ENVELOPE_VERSION,
            "unsupported canonical Contacts action version"
        );
        self.preview.validate()?;
        anyhow::ensure!(
            self.preview_sha256 == immutable_arguments_hash(&serde_json::to_value(&self.preview)?)?,
            "Contacts preview hash does not match preview"
        );
        Ok(())
    }

    pub fn into_foundation_action(self) -> anyhow::Result<FoundationActionEnvelope> {
        self.validate()?;
        let approval_preview = FoundationActionPreview::new(
            contact_risk_summary(&self.preview),
            contact_preview_details(&self.preview),
        )?;
        FoundationActionEnvelope::new(
            CONTACT_UPDATE_ACTION_KIND,
            CONTACTS_CONNECTOR_ID,
            CONTACT_UPDATE_OPERATION,
            self.preview.account_id.clone(),
            FoundationActionResource::new(
                "contact",
                self.preview.contact_id.clone(),
                Some(self.preview.expected_version.to_string()),
            )?,
            FoundationActionEffect::ExternalWrite,
            self.preview.idempotency_key.clone(),
            serde_json::to_value(self)?,
            approval_preview,
        )
    }

    pub fn from_foundation_action(envelope: &FoundationActionEnvelope) -> anyhow::Result<Self> {
        envelope.validate()?;
        anyhow::ensure!(
            envelope.kind == CONTACT_UPDATE_ACTION_KIND
                && envelope.connector_id == CONTACTS_CONNECTOR_ID
                && envelope.operation == CONTACT_UPDATE_OPERATION,
            "Foundation Action is not a canonical Contacts update"
        );
        let action: Self = serde_json::from_value(envelope.payload.clone())?;
        action.validate()?;
        let expected = action.clone().into_foundation_action()?;
        anyhow::ensure!(
            envelope.account_id == expected.account_id
                && envelope.resource == expected.resource
                && envelope.effect == expected.effect
                && envelope.idempotency_key == expected.idempotency_key
                && envelope.preview == expected.preview,
            "canonical Contacts action binding is invalid"
        );
        Ok(action)
    }
}

fn contact_risk_summary(preview: &ContactMutationPreview) -> String {
    format!(
        "Update contact {:?} in account {}",
        preview.replacement.display_name, preview.account_id
    )
    .chars()
    .take(1024)
    .collect()
}

fn contact_preview_details(preview: &ContactMutationPreview) -> Value {
    json!({
        "contactId": preview.contact_id,
        "expectedVersion": preview.expected_version,
        "replacement": preview.replacement,
        "previewHash": preview.preview_hash,
    })
}

#[cfg(test)]
#[path = "contacts_action_envelope_tests.rs"]
mod tests;

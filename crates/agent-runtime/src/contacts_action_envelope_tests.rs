use super::*;
use crate::contacts::{ContactIdentity, ContactRecord};
use chrono::Utc;

fn preview() -> ContactMutationPreview {
    ContactMutationPreview {
        preview_id: "preview-1".into(),
        account_id: "primary".into(),
        contact_id: "contact-1".into(),
        expected_version: 2,
        replacement: ContactRecord {
            id: "contact-1".into(),
            display_name: "Alex Chen".into(),
            identities: vec![ContactIdentity {
                kind: "email".into(),
                value: "alex@example.test".into(),
                label: Some("work".into()),
            }],
            organization: Some("Example".into()),
            relationship: Some("Customer".into()),
            version: 3,
            provider_id: Some("provider-1".into()),
            updated_at: Utc::now(),
        },
        preview_hash: "a".repeat(64),
        idempotency_key: "update-1".into(),
    }
}

#[test]
fn canonical_contact_update_round_trips() {
    let canonical = CanonicalContactActionEnvelope::from_preview(preview()).unwrap();
    let foundation = canonical.clone().into_foundation_action().unwrap();
    assert_eq!(foundation.kind, CONTACT_UPDATE_ACTION_KIND);
    assert_eq!(
        CanonicalContactActionEnvelope::from_foundation_action(&foundation).unwrap(),
        canonical
    );
}

#[test]
fn canonical_contact_update_rejects_resource_drift() {
    let mut foundation = CanonicalContactActionEnvelope::from_preview(preview())
        .unwrap()
        .into_foundation_action()
        .unwrap();
    foundation.resource.expected_revision = Some("3".into());
    assert!(CanonicalContactActionEnvelope::from_foundation_action(&foundation).is_err());
}

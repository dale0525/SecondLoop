use super::*;

fn scope(user: &str) -> ContactScope {
    ContactScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: user.into(),
        account_id: "primary".into(),
    }
}

fn contact(id: &str, name: &str, email: &str) -> ContactRecord {
    ContactRecord {
        id: id.into(),
        display_name: name.into(),
        identities: vec![ContactIdentity {
            kind: "email".into(),
            value: email.into(),
            label: None,
        }],
        organization: None,
        relationship: None,
        version: 1,
        provider_id: Some(format!("provider-{id}")),
        updated_at: Utc::now(),
    }
}

#[tokio::test]
async fn ambiguous_resolution_stays_explicit_and_updates_require_exact_approval() {
    let connector = FakeContactsConnector::default();
    connector
        .seed(
            scope("user"),
            contact("one", "Alex Chen", "alex.one@example.test"),
        )
        .unwrap();
    connector
        .seed(
            scope("user"),
            contact("two", "Alex Chen", "alex.two@example.test"),
        )
        .unwrap();
    assert_eq!(
        connector
            .resolve(&scope("user"), "Alex", 10)
            .await
            .unwrap()
            .len(),
        2
    );
    assert!(
        connector
            .resolve(&scope("other"), "Alex", 10)
            .await
            .unwrap()
            .is_empty()
    );
    let preview = connector
        .preview_update(
            &scope("user"),
            "one",
            1,
            contact("ignored", "Alex Chen", "new@example.test"),
            "update-1".into(),
        )
        .await
        .unwrap();
    let replayed_preview = connector
        .preview_update(
            &scope("user"),
            "one",
            1,
            contact("ignored", "Alex Chen", "new@example.test"),
            "update-1".into(),
        )
        .await
        .unwrap();
    assert_eq!(preview, replayed_preview);
    let wrong = ApprovedContactMutation {
        preview_id: preview.preview_id.clone(),
        preview_hash: "0".repeat(64),
        approval_id: "approval-1".into(),
    };
    assert!(connector.apply(&scope("user"), wrong).await.is_err());
    let approved = ApprovedContactMutation {
        preview_id: preview.preview_id,
        preview_hash: preview.preview_hash,
        approval_id: "approval-1".into(),
    };
    let first = connector
        .apply(&scope("user"), approved.clone())
        .await
        .unwrap();
    let second = connector.apply(&scope("user"), approved).await.unwrap();
    assert_eq!(first, second);
    assert_eq!(first.version, 2);
    assert_eq!(first.provider_id.as_deref(), Some("provider-one"));
}

use crate::skill_authoring_tests::AuthoringFixture;
use crate::skill_recovery_tests::activate_new_revision;
use crate::skill_state::NewSkillApproval;
use crate::skill_store::{SkillStoreFaultPoint, SkillStoreTestFaults};
use serde_json::json;

#[tokio::test]
async fn cleanup_retains_a_revision_reachable_from_a_live_snapshot_lease() {
    let fixture = AuthoringFixture::new().await;
    let first = activate_new_revision(&fixture, "1.0.0").await;
    let lease = fixture.manager.lease_snapshot();
    activate_new_revision(&fixture, "2.0.0").await;
    activate_new_revision(&fixture, "3.0.0").await;
    let record = fixture.state.get_revision(&first).await.unwrap().unwrap();

    fixture
        .manager
        .cleanup_unreferenced_revisions()
        .await
        .unwrap();
    assert!(std::path::Path::new(&record.storage_path).is_dir());

    drop(lease);
    let report = fixture
        .manager
        .cleanup_unreferenced_revisions()
        .await
        .unwrap();
    assert_eq!(report.deleted_revisions, vec![first.clone()]);
    assert!(!std::path::Path::new(&record.storage_path).exists());
    assert!(fixture.state.get_revision(&first).await.unwrap().is_none());
}

#[tokio::test]
async fn cleanup_retains_a_revision_bound_to_a_pending_approval() {
    let fixture = AuthoringFixture::new().await;
    let first = activate_new_revision(&fixture, "1.0.0").await;
    activate_new_revision(&fixture, "2.0.0").await;
    activate_new_revision(&fixture, "3.0.0").await;
    let package_id = crate::skill_package::SkillPackageId::parse("com.example.calendar").unwrap();
    let approval = fixture
        .state
        .create_approval(NewSkillApproval {
            package_id,
            revision_id: first.clone(),
            operation: "rollback".into(),
            requested_by: "owner-1".into(),
            permission_diff: json!({}),
            binding: Some(json!({"revisionId": first})),
        })
        .await
        .unwrap();

    fixture
        .manager
        .cleanup_unreferenced_revisions()
        .await
        .unwrap();
    assert!(fixture.state.get_revision(&first).await.unwrap().is_some());

    fixture
        .state
        .reject(&approval.approval_id, "approver-2")
        .await
        .unwrap();
    fixture
        .manager
        .cleanup_unreferenced_revisions()
        .await
        .unwrap();
    assert!(fixture.state.get_revision(&first).await.unwrap().is_none());
}

#[tokio::test]
async fn cleanup_after_tree_delete_failure_leaves_a_retryable_durable_job() {
    let faults = SkillStoreTestFaults::default();
    faults.fail_once(SkillStoreFaultPoint::CleanupAfterTreeDelete);
    let fixture = AuthoringFixture::with_faults(faults).await;
    let first = activate_new_revision(&fixture, "1.0.0").await;
    activate_new_revision(&fixture, "2.0.0").await;
    activate_new_revision(&fixture, "3.0.0").await;
    let record = fixture.state.get_revision(&first).await.unwrap().unwrap();

    fixture
        .manager
        .cleanup_unreferenced_revisions()
        .await
        .unwrap_err();

    assert!(!std::path::Path::new(&record.storage_path).exists());
    assert!(fixture.state.get_revision(&first).await.unwrap().is_some());
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM skill_revision_cleanup WHERE revision_id = ? AND status = 'pending'",
    )
    .bind(&first)
    .fetch_one(fixture.state.pool())
    .await
    .unwrap();
    assert_eq!(pending, 1);
    let diagnostics: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM skill_maintenance_diagnostics WHERE revision_id = ? AND operation = 'cleanup_unreferenced_revision_failed'",
    )
    .bind(&first)
    .fetch_one(fixture.state.pool())
    .await
    .unwrap();
    assert_eq!(diagnostics, 1);
    let audit: (String, String) = sqlx::query_as(
        r#"SELECT result, metadata_json FROM skill_audit_log
           WHERE operation = 'cleanup_unreferenced_revision'
             AND package_id = ? AND revision_id = ?"#,
    )
    .bind("com.example.calendar")
    .bind(&first)
    .fetch_one(fixture.state.pool())
    .await
    .unwrap();
    assert_eq!(audit.0, "error");
    assert!(audit.1.contains("retryable"));
    assert!(!audit.1.contains(&record.storage_path));

    fixture
        .manager
        .cleanup_unreferenced_revisions()
        .await
        .unwrap();
    assert!(fixture.state.get_revision(&first).await.unwrap().is_none());
}

#[cfg(unix)]
#[tokio::test]
async fn cleanup_never_deletes_a_replacement_at_the_observed_path() {
    let faults = SkillStoreTestFaults::default();
    let gate = faults.gate_once(SkillStoreFaultPoint::CleanupBeforeTreeDelete);
    let fixture = AuthoringFixture::with_faults(faults).await;
    let first = activate_new_revision(&fixture, "1.0.0").await;
    activate_new_revision(&fixture, "2.0.0").await;
    activate_new_revision(&fixture, "3.0.0").await;
    let record = fixture.state.get_revision(&first).await.unwrap().unwrap();
    let observed = std::path::PathBuf::from(&record.storage_path);
    let displaced = observed.with_extension("displaced");

    let manager = fixture.manager.clone();
    let cleanup = tokio::spawn(async move { manager.cleanup_unreferenced_revisions().await });
    gate.wait_entered().await;
    make_directory_replaceable(&observed).await;
    tokio::fs::rename(&observed, &displaced).await.unwrap();
    tokio::fs::create_dir(&observed).await.unwrap();
    tokio::fs::write(observed.join("replacement-marker"), b"preserve")
        .await
        .unwrap();
    gate.release().await;

    cleanup.await.unwrap().unwrap_err();
    assert_eq!(
        tokio::fs::read(observed.join("replacement-marker"))
            .await
            .unwrap(),
        b"preserve"
    );
    assert!(fixture.state.get_revision(&first).await.unwrap().is_some());
}

#[cfg(unix)]
async fn make_directory_replaceable(path: &std::path::Path) {
    use std::os::unix::fs::PermissionsExt;

    for path in [path, path.parent().unwrap()] {
        let mut permissions = tokio::fs::metadata(path).await.unwrap().permissions();
        permissions.set_mode(permissions.mode() | 0o300);
        tokio::fs::set_permissions(path, permissions).await.unwrap();
    }
}

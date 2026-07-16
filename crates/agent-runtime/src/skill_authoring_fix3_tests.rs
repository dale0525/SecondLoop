use crate::skill_authoring_tests::AuthoringFixture;
use crate::skill_management::CreateSkillDraftRequest;
use crate::skill_management::DraftFileUpdate;
use crate::skill_management_tools::{SkillManagementToolContext, SkillManagementTools};
use crate::skill_package::{SkillPackageId, SkillPackageKind};
use crate::skill_policy::{ActorContext, SkillGrant};
use crate::skill_state::{SkillApprovalStatus, SkillRevisionStatus};
use crate::skill_store::{SkillStoreFaultPoint, SkillStoreTestFaults};
use std::path::{Path, PathBuf};

#[tokio::test]
async fn prepared_destination_write_after_prepare_never_reaches_durable_commit() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, approval) = validated_activation(&fixture, "com.example.prepared-write").await;
    let prepare = faults.gate_once(SkillStoreFaultPoint::ActivationAfterPrepare);
    let durable = faults.gate_once(SkillStoreFaultPoint::ActivationAfterDurableCommit);
    let managed = managed_destination(&fixture, &draft.package_id, &draft.revision_id);
    let initial_snapshot_rows = snapshot_rows(&fixture).await;
    let initial_audit_count = audit_count(&fixture).await;
    let mut events = fixture.service.subscribe_events();
    let waiter = spawn_approval(&fixture, &approval.approval_id);
    prepare.wait_entered().await;
    make_file_writable(&managed.join("SKILL.md")).await;
    tokio::fs::write(managed.join("SKILL.md"), "changed after prepare")
        .await
        .unwrap();

    prepare.release().await;
    let entered_durable = release_if_entered(&durable).await;
    let error = waiter.await.unwrap().unwrap_err();

    assert!(
        !entered_durable,
        "modified destination reached durable commit"
    );
    assert_precommit_failure(&fixture, &draft, &approval.approval_id).await;
    assert!(!managed.exists());
    assert_eq!(snapshot_rows(&fixture).await, initial_snapshot_rows);
    assert_eq!(audit_count(&fixture).await, initial_audit_count);
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(20), events.recv())
            .await
            .is_err()
    );
    assert!(!error.to_string().contains(managed.to_str().unwrap()));
}

#[tokio::test]
async fn prepared_destination_replacement_is_rejected_without_deleting_replacement() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, approval) = validated_activation(&fixture, "com.example.prepared-replace").await;
    let built = faults.gate_once(SkillStoreFaultPoint::ActivationAfterCandidateBuild);
    let durable = faults.gate_once(SkillStoreFaultPoint::ActivationAfterDurableCommit);
    let managed = managed_destination(&fixture, &draft.package_id, &draft.revision_id);
    let displaced = managed.with_extension("approved-displaced");
    let waiter = spawn_approval(&fixture, &approval.approval_id);
    built.wait_entered().await;
    make_directory_replaceable(&managed).await;
    tokio::fs::rename(&managed, &displaced).await.unwrap();
    tokio::fs::create_dir(&managed).await.unwrap();
    tokio::fs::write(managed.join("replacement-marker"), "external replacement")
        .await
        .unwrap();

    built.release().await;
    let entered_durable = release_if_entered(&durable).await;
    waiter.await.unwrap().unwrap_err();

    assert!(
        !entered_durable,
        "replaced destination reached durable commit"
    );
    assert_precommit_failure(&fixture, &draft, &approval.approval_id).await;
    assert_eq!(
        tokio::fs::read_to_string(managed.join("replacement-marker"))
            .await
            .unwrap(),
        "external replacement"
    );
    assert!(displaced.is_dir());
}

#[tokio::test]
async fn activation_request_edit_before_commit_creates_no_approval_audit_or_event() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, _) =
        validated_activation_without_request(&fixture, "com.example.request-edit-cas").await;
    let before = faults.gate_once(SkillStoreFaultPoint::ActivationRequestBeforeCommit);
    let mut events = fixture.service.subscribe_events();
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Activate]);
    let revision_id = draft.revision_id.clone();
    let waiter =
        tokio::spawn(async move { service.request_activation(&actor, &revision_id).await });
    before.wait_entered().await;
    fixture
        .service
        .update_draft(
            &fixture.actor([SkillGrant::EditDraft]),
            &draft.revision_id,
            vec![DraftFileUpdate {
                path: "references/request-race.md".into(),
                content: "Edited before request commit.\n".into(),
            }],
        )
        .await
        .unwrap();
    before.release().await;

    let error = waiter.await.unwrap().unwrap_err();
    assert_conflict(&error);
    assert_no_approval_terminal_effects(&fixture, &draft.revision_id, &mut events).await;

    fixture
        .service
        .validate_draft(&fixture.actor([SkillGrant::Validate]), &draft.revision_id)
        .await
        .unwrap();
    let fresh = fixture
        .service
        .request_activation(&fixture.actor([SkillGrant::Activate]), &draft.revision_id)
        .await
        .unwrap();
    assert_eq!(fresh.status, SkillApprovalStatus::Pending);
    assert!(matches!(
        events.recv().await.unwrap(),
        crate::events::RuntimeEvent::SkillApprovalRequired { approval_id, .. }
            if approval_id == fresh.approval_id
    ));
}

#[tokio::test]
async fn activation_request_generation_publish_before_commit_creates_no_false_event() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, _) =
        validated_activation_without_request(&fixture, "com.example.request-generation-cas").await;
    let before = faults.gate_once(SkillStoreFaultPoint::ActivationRequestBeforeCommit);
    let mut events = fixture.service.subscribe_events();
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Activate]);
    let revision_id = draft.revision_id.clone();
    let waiter =
        tokio::spawn(async move { service.request_activation(&actor, &revision_id).await });
    before.wait_entered().await;
    fixture.manager.reload().await.unwrap();
    before.release().await;

    let error = waiter.await.unwrap().unwrap_err();
    assert_conflict(&error);
    assert_eq!(fixture.manager.current_snapshot().generation(), 2);
    assert_no_approval_terminal_effects(&fixture, &draft.revision_id, &mut events).await;

    fixture
        .service
        .validate_draft(&fixture.actor([SkillGrant::Validate]), &draft.revision_id)
        .await
        .unwrap();
    fixture
        .service
        .request_activation(&fixture.actor([SkillGrant::Activate]), &draft.revision_id)
        .await
        .unwrap();
    assert!(matches!(
        events.recv().await.unwrap(),
        crate::events::RuntimeEvent::SkillApprovalRequired { .. }
    ));
}

#[tokio::test]
async fn draft_test_holds_generation_guard_through_result_persistence() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, _) =
        validated_activation_without_request(&fixture, "com.example.test-generation-guard").await;
    let before = faults.gate_once(SkillStoreFaultPoint::DraftTestBeforePersist);
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Test]);
    let revision_id = draft.revision_id.clone();
    let test_waiter = tokio::spawn(async move { service.test_draft(&actor, &revision_id).await });
    before.wait_entered().await;

    let manager = fixture.manager.clone();
    let mut reload = tokio::spawn(async move { manager.reload().await });
    let early_reload =
        tokio::time::timeout(std::time::Duration::from_millis(100), &mut reload).await;
    let reload_was_blocked = early_reload.is_err();
    before.release().await;
    let test_result = test_waiter.await.unwrap().unwrap();
    let reload_report = match early_reload {
        Ok(result) => result.unwrap().unwrap(),
        Err(_) => reload.await.unwrap().unwrap(),
    };

    assert!(
        reload_was_blocked,
        "reload published before draft-test persistence"
    );
    assert!(test_result.ok);
    assert_eq!(test_result.snapshot_generation, 1);
    let persisted = fixture
        .state
        .revision_validation(&draft.revision_id)
        .await
        .unwrap();
    assert_eq!(persisted["test"]["ok"], true);
    assert_eq!(persisted["test"]["snapshotGeneration"], 1);
    assert_eq!(reload_report.previous_generation, 1);
    assert_eq!(reload_report.active_generation, 2);
}

#[tokio::test]
async fn activation_publication_lease_orders_event_before_next_generation_and_cleanup() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (_, approval) =
        validated_activation(&fixture, "com.example.activation-publication-lease").await;
    let after_memory = faults.gate_once(SkillStoreFaultPoint::ActivationAfterMemoryPublish);
    let after_cleanup = faults.gate_once(SkillStoreFaultPoint::ActivationAfterSourceCleanup);
    let mut events = fixture.service.subscribe_events();
    let activation = spawn_approval(&fixture, &approval.approval_id);
    after_memory.wait_entered().await;
    assert_eq!(fixture.manager.current_snapshot().generation(), 2);

    let manager = fixture.manager.clone();
    let mut reload = tokio::spawn(async move { manager.reload().await });
    let early_reload =
        tokio::time::timeout(std::time::Duration::from_millis(100), &mut reload).await;
    let reload_published_before_event = early_reload.is_ok();

    after_memory.release().await;
    let event = tokio::time::timeout(std::time::Duration::from_secs(1), events.recv())
        .await
        .expect("activation publication event must arrive")
        .unwrap();
    after_cleanup.wait_entered().await;
    let reload_blocked_through_cleanup = !reload.is_finished();
    after_cleanup.release().await;

    let activation_report = activation.await.unwrap().unwrap();
    let reload_report = match early_reload {
        Ok(result) => result.unwrap().unwrap(),
        Err(_) => reload.await.unwrap().unwrap(),
    };
    assert!(
        !reload_published_before_event,
        "generation N+1 published before generation N event"
    );
    assert!(
        reload_blocked_through_cleanup,
        "publication lease ended before activation terminal cleanup"
    );
    assert!(matches!(
        event,
        crate::events::RuntimeEvent::SkillSnapshotPublished { generation: 2 }
    ));
    assert_eq!(activation_report.active_generation, 2);
    assert_eq!(reload_report.previous_generation, 2);
    assert_eq!(reload_report.active_generation, 3);
}

#[tokio::test]
async fn draft_test_timeout_waits_for_publication_lease_and_persists_once() {
    let fixture = AuthoringFixture::new().await;
    let (draft, _) =
        validated_activation_without_request(&fixture, "com.example.timeout-publication-lease")
            .await;
    let publication = fixture.manager.begin_publication().await.unwrap();
    let service = fixture
        .service
        .clone()
        .with_draft_test_deadline(std::time::Duration::from_millis(30));
    let actor = fixture.actor([SkillGrant::Test]);
    let revision_id = draft.revision_id.clone();
    let waiter = tokio::spawn(async move { service.test_draft(&actor, &revision_id).await });

    tokio::time::sleep(std::time::Duration::from_millis(650)).await;
    let waiter_finished_while_serialization_was_busy = waiter.is_finished();
    drop(publication);
    let result = tokio::time::timeout(std::time::Duration::from_secs(1), waiter)
        .await
        .expect("timeout terminalization must finish after publication lease release")
        .unwrap()
        .unwrap();
    let persisted = fixture
        .state
        .revision_validation(&draft.revision_id)
        .await
        .unwrap();

    assert!(
        !waiter_finished_while_serialization_was_busy,
        "terminal continuation was cancelled by a secondary timeout"
    );
    assert!(!result.ok);
    assert_eq!(result.error_class.as_deref(), Some("timeout"));
    assert_eq!(persisted["test"], serde_json::to_value(&result).unwrap());
    assert_eq!(fixture.manager.current_snapshot().generation(), 1);
    assert!(
        fixture
            .state
            .get_installation(&draft.package_id)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn malformed_revision_id_is_invalid_for_service_and_model_tool() {
    let fixture = AuthoringFixture::new().await;
    let actor = fixture.actor([SkillGrant::Validate]);
    let error = fixture
        .service
        .validate_draft(&actor, "private-not-a-revision")
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref::<crate::skill_management::SkillManagementError>(),
        Some(crate::skill_management::SkillManagementError::InvalidRequest(_))
    ));
    assert!(!error.to_string().contains("private-not-a-revision"));

    let result = SkillManagementTools::execute(
        &SkillManagementToolContext {
            service: fixture.service.clone(),
            actor,
        },
        "validate_skill_draft",
        "malformed-revision",
        serde_json::json!({"revision_id": "private-not-a-revision"}),
    )
    .await;
    assert!(!result.ok);
    let tool_error = result.error.unwrap();
    assert_eq!(tool_error.code, "invalid_arguments");
    assert!(!tool_error.message.contains("private-not-a-revision"));
}

#[tokio::test]
async fn validate_edit_cas_loss_is_typed_conflict_without_stale_validation() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let draft = create_draft(&fixture, "com.example.validate-edit-cas").await;
    let gate = faults.gate_once(SkillStoreFaultPoint::ValidateDraftBeforePersist);
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Validate]);
    let revision_id = draft.revision_id.clone();
    let waiter = tokio::spawn(async move { service.validate_draft(&actor, &revision_id).await });
    gate.wait_entered().await;
    fixture
        .service
        .update_draft(
            &fixture.actor([SkillGrant::EditDraft]),
            &draft.revision_id,
            vec![DraftFileUpdate {
                path: "references/validate-race.md".into(),
                content: "Concurrent edit.\n".into(),
            }],
        )
        .await
        .unwrap();
    gate.release().await;

    let error = waiter.await.unwrap().unwrap_err();
    assert_conflict(&error);
    let record = fixture
        .state
        .get_revision(&draft.revision_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        record.validation_json,
        serde_json::json!({"status": "pending"})
    );
}

#[tokio::test]
async fn draft_test_edit_cas_loss_is_typed_conflict_without_stale_test_document() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, _) =
        validated_activation_without_request(&fixture, "com.example.test-edit-cas").await;
    let gate = faults.gate_once(SkillStoreFaultPoint::DraftTestBeforePersist);
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Test]);
    let revision_id = draft.revision_id.clone();
    let waiter = tokio::spawn(async move { service.test_draft(&actor, &revision_id).await });
    gate.wait_entered().await;
    fixture
        .service
        .update_draft(
            &fixture.actor([SkillGrant::EditDraft]),
            &draft.revision_id,
            vec![DraftFileUpdate {
                path: "references/test-race.md".into(),
                content: "Concurrent edit.\n".into(),
            }],
        )
        .await
        .unwrap();
    gate.release().await;

    let error = waiter.await.unwrap().unwrap_err();
    assert_conflict(&error);
    let record = fixture
        .state
        .get_revision(&draft.revision_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        record.validation_json,
        serde_json::json!({"status": "pending"})
    );
}

#[tokio::test]
async fn concurrent_validations_use_exact_revision_cas() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let draft = create_draft(&fixture, "com.example.validate-validate-cas").await;
    let gate = faults.gate_once(SkillStoreFaultPoint::ValidateDraftBeforePersist);
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Validate]);
    let revision_id = draft.revision_id.clone();
    let first = tokio::spawn(async move { service.validate_draft(&actor, &revision_id).await });
    gate.wait_entered().await;

    let second = fixture
        .service
        .validate_draft(&fixture.actor([SkillGrant::Validate]), &draft.revision_id)
        .await
        .unwrap();
    gate.release().await;
    let first_error = first.await.unwrap().unwrap_err();

    assert!(second.ok);
    assert_conflict(&first_error);
    let persisted = fixture
        .state
        .revision_validation(&draft.revision_id)
        .await
        .unwrap();
    assert_eq!(persisted["contentHash"], second.content_hash);
    assert!(persisted.get("test").is_none());
}

#[tokio::test]
async fn concurrent_draft_tests_serialize_generation_and_use_exact_revision_cas() {
    let faults = SkillStoreTestFaults::default();
    let fixture = AuthoringFixture::with_faults(faults.clone()).await;
    let (draft, _) =
        validated_activation_without_request(&fixture, "com.example.test-test-cas").await;
    let persist_gate = faults.gate_once(SkillStoreFaultPoint::DraftTestBeforePersist);
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Test]);
    let revision_id = draft.revision_id.clone();
    let first = tokio::spawn(async move { service.test_draft(&actor, &revision_id).await });
    persist_gate.wait_entered().await;

    let preview_gate = faults.gate_once(SkillStoreFaultPoint::DraftTestBeforePreview);
    let service = fixture.service.clone();
    let actor = fixture.actor([SkillGrant::Test]);
    let revision_id = draft.revision_id.clone();
    let mut second = tokio::spawn(async move { service.test_draft(&actor, &revision_id).await });
    preview_gate.wait_entered().await;
    preview_gate.release().await;
    let early_second =
        tokio::time::timeout(std::time::Duration::from_millis(100), &mut second).await;
    let second_waited = early_second.is_err();
    persist_gate.release().await;

    let first_result = first.await.unwrap().unwrap();
    let second_result = match early_second {
        Ok(result) => result.unwrap(),
        Err(_) => second.await.unwrap(),
    };
    assert!(second_waited, "second draft test bypassed generation guard");
    assert!(first_result.ok);
    assert_conflict(&second_result.unwrap_err());
    let persisted = fixture
        .state
        .revision_validation(&draft.revision_id)
        .await
        .unwrap();
    assert_eq!(persisted["test"]["ok"], true);
    assert_eq!(persisted["test"]["snapshotGeneration"], 1);
}

#[tokio::test]
async fn model_tools_map_validate_and_test_edit_cas_losses_to_conflict() {
    let validate_faults = SkillStoreTestFaults::default();
    let validate_fixture = AuthoringFixture::with_faults(validate_faults.clone()).await;
    let validate_draft = create_draft(&validate_fixture, "com.example.model-validate-cas").await;
    let validate_gate = validate_faults.gate_once(SkillStoreFaultPoint::ValidateDraftBeforePersist);
    let validate_context = SkillManagementToolContext {
        service: validate_fixture.service.clone(),
        actor: validate_fixture.actor([SkillGrant::Validate]),
    };
    let validate_revision = validate_draft.revision_id.clone();
    let validate_waiter = tokio::spawn(async move {
        SkillManagementTools::execute(
            &validate_context,
            "validate_skill_draft",
            "validate-cas",
            serde_json::json!({"revision_id": validate_revision}),
        )
        .await
    });
    validate_gate.wait_entered().await;
    validate_fixture
        .service
        .update_draft(
            &validate_fixture.actor([SkillGrant::EditDraft]),
            &validate_draft.revision_id,
            vec![DraftFileUpdate {
                path: "references/model-validate-race.md".into(),
                content: "Concurrent edit.\n".into(),
            }],
        )
        .await
        .unwrap();
    validate_gate.release().await;
    let validate_result = validate_waiter.await.unwrap();
    assert!(!validate_result.ok);
    let validate_error = validate_result.error.unwrap();
    assert_eq!(validate_error.code, "conflict");
    assert!(!validate_error.message.contains(&validate_draft.revision_id));

    let test_faults = SkillStoreTestFaults::default();
    let test_fixture = AuthoringFixture::with_faults(test_faults.clone()).await;
    let (test_draft, _) =
        validated_activation_without_request(&test_fixture, "com.example.model-test-cas").await;
    let test_gate = test_faults.gate_once(SkillStoreFaultPoint::DraftTestBeforePersist);
    let test_context = SkillManagementToolContext {
        service: test_fixture.service.clone(),
        actor: test_fixture.actor([SkillGrant::Test]),
    };
    let test_revision = test_draft.revision_id.clone();
    let test_waiter = tokio::spawn(async move {
        SkillManagementTools::execute(
            &test_context,
            "test_skill_draft",
            "test-cas",
            serde_json::json!({"revision_id": test_revision}),
        )
        .await
    });
    test_gate.wait_entered().await;
    test_fixture
        .service
        .update_draft(
            &test_fixture.actor([SkillGrant::EditDraft]),
            &test_draft.revision_id,
            vec![DraftFileUpdate {
                path: "references/model-test-race.md".into(),
                content: "Concurrent edit.\n".into(),
            }],
        )
        .await
        .unwrap();
    test_gate.release().await;
    let test_result = test_waiter.await.unwrap();
    assert!(!test_result.ok);
    let test_error = test_result.error.unwrap();
    assert_eq!(test_error.code, "conflict");
    assert!(!test_error.message.contains(&test_draft.revision_id));
}

async fn validated_activation(
    fixture: &AuthoringFixture,
    package_id: &str,
) -> (
    crate::skill_management::SkillDraftSummary,
    crate::skill_state::SkillApprovalRecord,
) {
    let (draft, ()) = validated_activation_without_request(fixture, package_id).await;
    let approval = fixture
        .service
        .request_activation(&fixture.actor([SkillGrant::Activate]), &draft.revision_id)
        .await
        .unwrap();
    (draft, approval)
}

async fn validated_activation_without_request(
    fixture: &AuthoringFixture,
    package_id: &str,
) -> (crate::skill_management::SkillDraftSummary, ()) {
    let draft = create_draft(fixture, package_id).await;
    fixture
        .service
        .validate_draft(&fixture.actor([SkillGrant::Validate]), &draft.revision_id)
        .await
        .unwrap();
    (draft, ())
}

async fn create_draft(
    fixture: &AuthoringFixture,
    package_id: &str,
) -> crate::skill_management::SkillDraftSummary {
    fixture
        .service
        .create_draft(
            &fixture.actor([SkillGrant::CreateDraft]),
            CreateSkillDraftRequest {
                package_id: SkillPackageId::parse(package_id).unwrap(),
                display_name: "Final gate".into(),
                description: "Final gate activation.".into(),
                kind: SkillPackageKind::InstructionOnly,
                required_tools: Vec::new(),
            },
        )
        .await
        .unwrap()
}

fn spawn_approval(
    fixture: &AuthoringFixture,
    approval_id: &str,
) -> tokio::task::JoinHandle<anyhow::Result<crate::skill_manager::SkillReloadReport>> {
    let service = fixture.service.clone();
    let approval_id = approval_id.to_string();
    tokio::spawn(async move {
        service
            .approve_activation(
                &approval_id,
                &ActorContext::owner("approver-final", [SkillGrant::Activate]),
            )
            .await
    })
}

async fn release_if_entered(gate: &crate::skill_store_faults::StoreTestGate) -> bool {
    if tokio::time::timeout(std::time::Duration::from_millis(100), gate.wait_entered())
        .await
        .is_err()
    {
        return false;
    }
    gate.release().await;
    true
}

async fn assert_precommit_failure(
    fixture: &AuthoringFixture,
    draft: &crate::skill_management::SkillDraftSummary,
    approval_id: &str,
) {
    assert_eq!(
        fixture
            .state
            .get_revision(&draft.revision_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        SkillRevisionStatus::Staging
    );
    assert_eq!(
        fixture
            .state
            .get_approval(approval_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        SkillApprovalStatus::Pending
    );
    assert!(
        fixture
            .state
            .get_installation(&draft.package_id)
            .await
            .unwrap()
            .is_none()
    );
    assert_eq!(fixture.manager.current_snapshot().generation(), 1);
}

fn managed_destination(
    fixture: &AuthoringFixture,
    package_id: &SkillPackageId,
    revision_id: &str,
) -> PathBuf {
    fixture
        .store
        .paths()
        .managed
        .join(package_id.as_str())
        .join("revisions")
        .join(revision_id)
}

async fn make_file_writable(path: &Path) {
    let mut permissions = tokio::fs::metadata(path).await.unwrap().permissions();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        permissions.set_mode(0o644);
    }
    #[cfg(not(unix))]
    permissions.set_readonly(false);
    tokio::fs::set_permissions(path, permissions).await.unwrap();
}

async fn make_directory_replaceable(path: &Path) {
    make_directory_writable(path).await;
    make_directory_writable(path.parent().unwrap()).await;
}

async fn make_directory_writable(path: &Path) {
    let mut permissions = tokio::fs::metadata(path).await.unwrap().permissions();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        permissions.set_mode(permissions.mode() | 0o300);
    }
    #[cfg(not(unix))]
    permissions.set_readonly(false);
    tokio::fs::set_permissions(path, permissions).await.unwrap();
}

async fn snapshot_rows(fixture: &AuthoringFixture) -> Vec<(i64, String, String)> {
    sqlx::query_as(
        "SELECT generation, status, members_json FROM skill_snapshots ORDER BY generation",
    )
    .fetch_all(fixture.state.pool())
    .await
    .unwrap()
}

async fn audit_count(fixture: &AuthoringFixture) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM skill_audit_log")
        .fetch_one(fixture.state.pool())
        .await
        .unwrap()
}

fn assert_conflict(error: &anyhow::Error) {
    assert!(matches!(
        error.downcast_ref::<crate::skill_management::SkillManagementError>(),
        Some(crate::skill_management::SkillManagementError::Conflict { .. })
    ));
}

async fn assert_no_approval_terminal_effects(
    fixture: &AuthoringFixture,
    revision_id: &str,
    events: &mut tokio::sync::broadcast::Receiver<crate::events::RuntimeEvent>,
) {
    let approvals: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM skill_approvals WHERE revision_id = ?")
            .bind(revision_id)
            .fetch_one(fixture.state.pool())
            .await
            .unwrap();
    let audits: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM skill_audit_log WHERE revision_id = ? AND operation = 'skill_approval_required'",
    )
    .bind(revision_id)
    .fetch_one(fixture.state.pool())
    .await
    .unwrap();
    assert_eq!(approvals, 0);
    assert_eq!(audits, 0);
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(20), events.recv())
            .await
            .is_err()
    );
}

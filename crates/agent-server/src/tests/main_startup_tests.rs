use super::*;

#[tokio::test]
async fn production_registry_selects_local_and_isolates_two_tenant_routers() {
    let skills_root = unique_test_dir("tenant-production-skills");
    let app_root = unique_test_dir("tenant-production-app");
    let cache_root = unique_test_dir("tenant-production-cache");
    tokio::fs::create_dir_all(&skills_root).await.unwrap();
    let registry = build_managed_tenant_registry(
        &skills_root,
        ManagedSkillsConfig {
            app_data_root: app_root.clone(),
            cache_root: cache_root.clone(),
        },
        server_skill_startup::BuiltinSkillsMode::Directory,
        SkillManagementPolicy::owner_only(),
        None,
        None,
    )
    .await
    .unwrap();
    let local = registry
        .for_tenant(agent_server::tenant_skills::SINGLE_USER_TENANT_ID)
        .await
        .unwrap();
    let alpha = registry.for_tenant("alpha").await.unwrap();
    let beta = registry.for_tenant("beta").await.unwrap();
    let revision = activate_tenant_fixture(&alpha.management).await;
    let alpha_session = alpha.storage.create_session("Alpha only").await.unwrap();

    let local_app = tenant_router(local.clone()).await;
    let alpha_app = tenant_router(alpha.clone()).await;
    let beta_app = tenant_router(beta.clone()).await;

    assert_eq!(
        session_status(&alpha_app, &alpha_session.id).await,
        StatusCode::OK
    );
    assert_eq!(
        session_status(&local_app, &alpha_session.id).await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        session_status(&beta_app, &alpha_session.id).await,
        StatusCode::NOT_FOUND
    );
    assert!(
        owner_managed_packages(&alpha_app)
            .await
            .contains(&"com.example.tenant-alpha".into())
    );
    assert!(owner_managed_packages(&local_app).await.is_empty());
    assert!(owner_managed_packages(&beta_app).await.is_empty());
    assert!(alpha.state.get_revision(&revision).await.unwrap().is_some());
    assert!(local.state.get_revision(&revision).await.unwrap().is_none());
    assert!(beta.state.get_revision(&revision).await.unwrap().is_none());

    remove_test_dir(skills_root).await;
    remove_test_dir(app_root).await;
    remove_test_dir(cache_root).await;
}

async fn tenant_router(
    runtime: Arc<agent_server::tenant_skills::TenantSkillRuntime>,
) -> axum::Router {
    let owner = build_tenant_owner_api_config(Some(test_owner_host()), &runtime, Vec::new())
        .await
        .unwrap()
        .unwrap();
    let state = build_tenant_app_state(
        runtime,
        CapturingModel {
            tool_names: Arc::new(Mutex::new(Vec::new())),
        },
        RuntimeConfig::read_only(".", ".").without_builtin_tools(),
        agent_runtime::prompt_composer::AppPromptConfig::default(),
        Some(owner),
    )
    .await
    .unwrap();
    api::router(Arc::new(state))
}

async fn session_status(app: &axum::Router, session_id: &str) -> StatusCode {
    app.clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/sessions/{session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
        .status()
}

async fn owner_managed_packages(app: &axum::Router) -> Vec<String> {
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/owner/skills")
                .header("authorization", "Bearer owner-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&body).unwrap();
    body["managed"]
        .as_array()
        .unwrap()
        .iter()
        .map(|skill| skill["package_id"].as_str().unwrap().to_string())
        .collect()
}

async fn activate_tenant_fixture(service: &OwnerSkillManagementService) -> String {
    let owner = ActorContext::owner(
        "alpha-owner",
        [
            SkillGrant::Inspect,
            SkillGrant::CreateDraft,
            SkillGrant::Validate,
            SkillGrant::Activate,
        ],
    );
    let draft = service
        .create_draft(
            &owner,
            agent_runtime::skill_management::CreateSkillDraftRequest {
                package_id: SkillPackageId::parse("com.example.tenant-alpha").unwrap(),
                display_name: "Tenant alpha".into(),
                description: "Alpha-only managed instruction.".into(),
                kind: agent_runtime::skill_package::SkillPackageKind::InstructionOnly,
                required_tools: Vec::new(),
            },
        )
        .await
        .unwrap();
    service
        .validate_draft(&owner, &draft.revision_id)
        .await
        .unwrap();
    let approval = service
        .request_activation(&owner, &draft.revision_id)
        .await
        .unwrap();
    service
        .approve_activation(
            &approval.approval_id,
            &ActorContext::owner("alpha-approver", [SkillGrant::Activate]),
        )
        .await
        .unwrap();
    draft.revision_id
}

#[tokio::test]
async fn production_owner_initialization_awaits_startup_reconciliation() {
    let root = unique_test_dir("startup-reconcile-skills");
    tokio::fs::create_dir_all(&root).await.unwrap();
    let app_root = unique_test_dir("startup-reconcile-app");
    let cache_root = unique_test_dir("startup-reconcile-cache");
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let loaded = load_skill_manager(
        &root,
        storage.clone(),
        Some(ManagedSkillsConfig {
            app_data_root: app_root.clone(),
            cache_root: cache_root.clone(),
        }),
    )
    .await
    .unwrap();
    let store = loaded.managed_store.clone().unwrap();
    let source = unique_test_dir("startup-reconcile-source");
    write_instruction_package(&source, "com.example.startup-row").await;
    let draft = store
        .create_staging_revision(&source, "owner")
        .await
        .unwrap();
    tokio::fs::remove_dir_all(&draft.path).await.unwrap();

    let config = build_owner_api_config(
        Some(test_owner_host()),
        &loaded,
        storage.clone(),
        Vec::new(),
    )
    .await
    .unwrap();

    assert!(config.is_some());
    assert!(
        SkillStateStore::new(storage)
            .get_revision(&draft.revision_id)
            .await
            .unwrap()
            .is_none()
    );
    remove_test_dir(root).await;
    remove_test_dir(app_root).await;
    remove_test_dir(cache_root).await;
    remove_test_dir(source).await;
}

#[tokio::test]
async fn production_owner_initialization_fails_closed_when_reconciliation_fails() {
    let root = unique_test_dir("startup-failure-skills");
    tokio::fs::create_dir_all(&root).await.unwrap();
    let app_root = unique_test_dir("startup-failure-app");
    let cache_root = unique_test_dir("startup-failure-cache");
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let loaded = load_skill_manager(
        &root,
        storage.clone(),
        Some(ManagedSkillsConfig {
            app_data_root: app_root.clone(),
            cache_root: cache_root.clone(),
        }),
    )
    .await
    .unwrap();
    tokio::fs::remove_dir_all(&app_root).await.unwrap();

    let result =
        build_owner_api_config(Some(test_owner_host()), &loaded, storage, Vec::new()).await;

    assert!(result.is_err());
    remove_test_dir(root).await;
    remove_test_dir(app_root).await;
    remove_test_dir(cache_root).await;
}

fn test_owner_host() -> OwnerHostConfig {
    owner_host_config_from_lookup(|name| match name {
        "AGENTWEAVE_SKILL_MANAGEMENT_MODE" => Some("owner_only".into()),
        "AGENTWEAVE_OWNER_TOKEN" => Some("owner-token".into()),
        "AGENTWEAVE_APPROVER_TOKEN" => Some("approver-token".into()),
        _ => None,
    })
    .unwrap()
    .unwrap()
}

#[tokio::test]
async fn production_owner_requests_removal_and_distinct_approver_resolves_it() {
    let root = unique_test_dir("owner-lifecycle-routes-skills");
    tokio::fs::create_dir_all(&root).await.unwrap();
    let app_root = unique_test_dir("owner-lifecycle-routes-app");
    let cache_root = unique_test_dir("owner-lifecycle-routes-cache");
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let loaded = load_skill_manager(
        &root,
        storage.clone(),
        Some(ManagedSkillsConfig {
            app_data_root: app_root.clone(),
            cache_root: cache_root.clone(),
        }),
    )
    .await
    .unwrap();
    let store = loaded.managed_store.clone().unwrap();
    let source = unique_test_dir("owner-removal-source");
    write_instruction_package(&source, "com.example.production-removal").await;
    let revision = store
        .create_staging_revision(&source, "local-owner")
        .await
        .unwrap();
    let revision = store.promote_revision(&revision.revision_id).await.unwrap();
    SkillStateStore::new(storage.clone())
        .activate_revision(
            &SkillPackageId::parse("com.example.production-removal").unwrap(),
            &revision.revision_id,
            SkillLayerRecord::Managed,
            "local-owner",
        )
        .await
        .unwrap();
    let owner = build_owner_api_config(
        Some(test_owner_host()),
        &loaded,
        storage.clone(),
        Vec::new(),
    )
    .await
    .unwrap()
    .unwrap();
    let state = Arc::new(api::AppState::new_with_model_skill_manager_and_owner(
        storage.clone(),
        CapturingModel {
            tool_names: Arc::new(Mutex::new(Vec::new())),
        },
        loaded.manager,
        RuntimeConfig::read_only(".", ".").without_builtin_tools(),
        owner,
    ));
    let app = api::router(state);
    let requested = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/owner/skills/com.example.production-removal")
                .header("authorization", "Bearer owner-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(requested.status(), StatusCode::ACCEPTED);
    let body = axum::body::to_bytes(requested.into_body(), usize::MAX)
        .await
        .unwrap();
    let approval: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let approval_id = approval["approval_id"].as_str().unwrap();
    let approved = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/owner/skills/approvals/{approval_id}"))
                .header("authorization", "Bearer approver-token")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"decision":"approve"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(approved.status(), StatusCode::OK);
    assert_eq!(
        SkillStateStore::new(storage)
            .get_installation(&SkillPackageId::parse("com.example.production-removal").unwrap())
            .await
            .unwrap()
            .unwrap()
            .status,
        agent_runtime::skill_state::SkillInstallStatus::Removed
    );
    remove_test_dir(root).await;
    remove_test_dir(app_root).await;
    remove_test_dir(cache_root).await;
    remove_test_dir(source).await;
}

#[tokio::test]
async fn production_loader_does_not_mutate_corrupt_active_before_lkg_reconcile() {
    let root = unique_test_dir("lkg-first-skills");
    tokio::fs::create_dir_all(&root).await.unwrap();
    let app_root = unique_test_dir("lkg-first-app");
    let cache_root = unique_test_dir("lkg-first-cache");
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let state = SkillStateStore::new(storage.clone());
    let paths = SkillStorePaths::prepare(&app_root, &cache_root)
        .await
        .unwrap();
    let store = SkillRevisionStore::new(paths, state.clone());
    let source_one = unique_test_dir("lkg-first-source-one");
    let source_two = unique_test_dir("lkg-first-source-two");
    write_instruction_package(&source_one, "com.example.lkg-first").await;
    write_instruction_package(&source_two, "com.example.lkg-first").await;
    let good = store
        .create_staging_revision(&source_one, "owner")
        .await
        .unwrap();
    let good = store.promote_revision(&good.revision_id).await.unwrap();
    state
        .activate_revision(
            &SkillPackageId::parse("com.example.lkg-first").unwrap(),
            &good.revision_id,
            SkillLayerRecord::Managed,
            "owner",
        )
        .await
        .unwrap();
    let bad = store
        .create_staging_revision(&source_two, "owner")
        .await
        .unwrap();
    let bad = store.promote_revision(&bad.revision_id).await.unwrap();
    state
        .activate_revision(
            &SkillPackageId::parse("com.example.lkg-first").unwrap(),
            &bad.revision_id,
            SkillLayerRecord::Managed,
            "owner",
        )
        .await
        .unwrap();
    let good_record = state
        .get_revision(&good.revision_id)
        .await
        .unwrap()
        .unwrap();
    let bad_record = state.get_revision(&bad.revision_id).await.unwrap().unwrap();
    let member = |revision: &agent_runtime::skill_state::SkillRevisionRecord| {
        serde_json::json!([{
            "packageId": revision.package_id.as_str(),
            "version": revision.version,
            "contentHash": revision.content_hash,
            "layer": "managed",
            "revisionId": revision.revision_id,
        }])
    };
    state
        .record_snapshot_candidate(1, member(&good_record))
        .await
        .unwrap();
    state.record_snapshot_activation(1).await.unwrap();
    state.mark_snapshot_last_known_good(1).await.unwrap();
    state
        .record_snapshot_candidate(2, member(&bad_record))
        .await
        .unwrap();
    state.record_snapshot_activation(2).await.unwrap();
    make_test_tree_writable(&bad.path).await;
    tokio::fs::write(bad.path.join("agentweave.json"), b"{}")
        .await
        .unwrap();
    let package_id = SkillPackageId::parse("com.example.lkg-first").unwrap();
    let audits_before = state.list_audit(&package_id).await.unwrap().len();

    let loaded = load_skill_manager(
        &root,
        storage.clone(),
        Some(ManagedSkillsConfig {
            app_data_root: app_root.clone(),
            cache_root: cache_root.clone(),
        }),
    )
    .await
    .unwrap();

    assert_eq!(
        state
            .get_revision(&bad.revision_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        agent_runtime::skill_state::SkillRevisionStatus::Managed
    );
    assert!(bad.path.is_dir());
    assert!(!store.paths().quarantine.join(&bad.revision_id).exists());
    let audits_after_load = state.list_audit(&package_id).await.unwrap().len();
    assert_eq!(audits_after_load, audits_before);
    assert_eq!(
        state.get_snapshot(2).await.unwrap().unwrap().status,
        agent_runtime::skill_state::SkillSnapshotStatus::Active
    );

    build_owner_api_config(Some(test_owner_host()), &loaded, storage, Vec::new())
        .await
        .unwrap();

    assert_eq!(
        state
            .get_revision(&bad.revision_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        agent_runtime::skill_state::SkillRevisionStatus::Quarantined
    );
    assert_eq!(loaded.manager.current_snapshot().generation(), 1);
    remove_test_dir(root).await;
    remove_test_dir(app_root).await;
    remove_test_dir(cache_root).await;
    remove_test_dir(source_one).await;
    remove_test_dir(source_two).await;
}

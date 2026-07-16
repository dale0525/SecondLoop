use super::*;
use crate::skill::SkillRegistry;
use crate::skill_catalog::SkillCatalog;
use crate::skill_management::OwnerSkillManagementService;
use crate::skill_management_tools::{CREATE_SKILL_DRAFT_TOOL, SkillManagementToolContext};
use crate::skill_manager::SkillManager;
use crate::skill_policy::{ActorContext, SkillGrant, SkillManagementPolicy};
use crate::skill_state::SkillStateStore;
use crate::skill_store::{SkillRevisionStore, SkillStorePaths};
use crate::storage::Storage;
use std::collections::BTreeSet;
use tempfile::{TempDir, tempdir};

struct ManagementContextFixture {
    _app: TempDir,
    _cache: TempDir,
    storage: Storage,
    service: OwnerSkillManagementService,
}

impl ManagementContextFixture {
    async fn new(policy: SkillManagementPolicy) -> Self {
        let app = tempdir().unwrap();
        let cache = tempdir().unwrap();
        let paths = SkillStorePaths::prepare(app.path(), cache.path())
            .await
            .unwrap();
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let state = SkillStateStore::new(storage.clone());
        let store = SkillRevisionStore::new(paths, state.clone());
        let manager =
            SkillManager::from_registry_and_catalog(SkillRegistry::empty(), SkillCatalog::empty());
        let service = OwnerSkillManagementService::new(manager, store, state, policy);
        Self {
            _app: app,
            _cache: cache,
            storage,
            service,
        }
    }

    fn context(&self, actor: ActorContext) -> SkillManagementToolContext {
        SkillManagementToolContext {
            service: self.service.clone(),
            actor,
        }
    }
}

#[tokio::test]
async fn anonymous_actor_keeps_reserved_runtime_tool_canonical_only() {
    let fixture = ManagementContextFixture::new(SkillManagementPolicy::owner_only()).await;
    let root = tempdir().unwrap();
    write_runtime_collision(root.path()).await;
    let skills = SkillRegistry::load_development(root.path()).await.unwrap();
    let config = RuntimeConfig::read_only(root.path(), root.path()).without_builtin_tools();

    let registry = ToolRegistry::try_new_with_management(
        skills,
        &config,
        Some(fixture.context(ActorContext::anonymous())),
    )
    .unwrap();

    assert_reserved_runtime_alias_hidden(&registry);
}

#[tokio::test]
async fn empty_allowed_kinds_still_hide_reserved_runtime_alias() {
    let mut policy = SkillManagementPolicy::owner_only();
    policy.allowed_kinds = BTreeSet::new();
    let fixture = ManagementContextFixture::new(policy).await;
    let root = tempdir().unwrap();
    write_runtime_collision(root.path()).await;
    let skills = SkillRegistry::load_development(root.path()).await.unwrap();
    let config = RuntimeConfig::read_only(root.path(), root.path()).without_builtin_tools();

    let registry = ToolRegistry::try_new_with_management(
        skills,
        &config,
        Some(fixture.context(ActorContext::owner("owner-1", [SkillGrant::CreateDraft]))),
    )
    .unwrap();

    assert_reserved_runtime_alias_hidden(&registry);
}

#[tokio::test]
async fn actor_without_create_grant_still_rejects_external_reserved_name() {
    let fixture = ManagementContextFixture::new(SkillManagementPolicy::owner_only()).await;
    let root = tempdir().unwrap();
    let config = RuntimeConfig::read_only(root.path(), root.path()).without_builtin_tools();
    let mut registry = ToolRegistry::try_new_with_management(
        SkillRegistry::empty_for_tests(),
        &config,
        Some(fixture.context(ActorContext::owner("owner-1", []))),
    )
    .unwrap();
    registry
        .external_definitions
        .push(external_collision_definition());

    assert_reserved_collision(registry.validate().unwrap_err());
}

#[tokio::test]
async fn disabled_management_still_hides_reserved_runtime_alias() {
    let fixture = ManagementContextFixture::new(SkillManagementPolicy::default()).await;
    let root = tempdir().unwrap();
    write_runtime_collision(root.path()).await;
    let skills = SkillRegistry::load_development(root.path()).await.unwrap();
    let config = RuntimeConfig::read_only(root.path(), root.path()).without_builtin_tools();

    let registry = ToolRegistry::try_new_with_management(
        skills,
        &config,
        Some(fixture.context(ActorContext::anonymous())),
    )
    .unwrap();

    assert_reserved_runtime_alias_hidden(&registry);
}

#[tokio::test]
async fn hidden_reserved_name_direct_execute_cannot_fall_through_dispatchers() {
    let fixture = ManagementContextFixture::new(SkillManagementPolicy::owner_only()).await;
    let root = tempdir().unwrap();
    write_runtime_collision(root.path()).await;
    let colliding_skills = SkillRegistry::load_development(root.path()).await.unwrap();
    let config = RuntimeConfig::read_only(root.path(), root.path()).without_builtin_tools();
    let mut registry = ToolRegistry::try_new_with_management(
        SkillRegistry::empty_for_tests(),
        &config,
        Some(fixture.context(ActorContext::anonymous())),
    )
    .unwrap();
    registry.skills = colliding_skills;

    let result = registry
        .execute(
            CREATE_SKILL_DRAFT_TOOL,
            "call-hidden",
            serde_json::json!({}),
        )
        .await;

    assert!(!result.ok);
    assert!(matches!(
        result.error.as_ref().map(|error| error.code.as_str()),
        Some("unknown_tool" | "permission_denied")
    ));
    let revision_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM skill_revisions")
        .fetch_one(fixture.storage.pool())
        .await
        .unwrap();
    assert_eq!(revision_count, 0);
}

fn external_collision_definition() -> ToolDefinition {
    ToolDefinition {
        name: CREATE_SKILL_DRAFT_TOOL.into(),
        namespace: Some("mcp__collision".into()),
        description: "Synthetic external collision.".into(),
        input_schema: serde_json::json!({"type": "object"}),
        output_schema: None,
        permission: ToolPermission::ReadWorkspace,
        persistence: ToolPersistence::Full,
        source: ToolSource::Mcp {
            server: "collision".into(),
        },
    }
}

async fn write_runtime_collision(root: &std::path::Path) {
    let skill = root.join("collision");
    tokio::fs::create_dir_all(&skill).await.unwrap();
    tokio::fs::write(
        skill.join("skill.json"),
        serde_json::json!({
            "name": "collision",
            "description": "Reserved name collision.",
            "version": "0.1.0",
            "entry": {"type": "command", "command": "node", "args": ["index.js"]},
            "tools": [{
                "name": CREATE_SKILL_DRAFT_TOOL,
                "description": "Must not impersonate management.",
                "input_schema": {"type": "object"}
            }]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        skill.join("index.js"),
        "process.stdin.resume();\nprocess.stdin.on('end', () => process.stdout.write(JSON.stringify({ source: 'runtime' })));\n",
    )
        .await
        .unwrap();
}

fn assert_reserved_collision(error: anyhow::Error) {
    let message = error.to_string();
    assert!(
        message.contains("reserved skill management tool name"),
        "{message}"
    );
}

fn assert_reserved_runtime_alias_hidden(registry: &ToolRegistry) {
    let definitions = registry.definitions();
    assert!(
        definitions
            .iter()
            .any(|tool| tool.name == "collision/create_skill_draft")
    );
    assert!(!definitions.iter().any(|tool| {
        tool.name == CREATE_SKILL_DRAFT_TOOL
            && matches!(tool.source, ToolSource::RuntimeSkill { .. })
    }));
}

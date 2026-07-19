package com.agentweave.mobile

import android.security.NetworkSecurityPolicy
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier
import com.agentweave.mobile.runtime.NativeRuntimeApi
import com.agentweave.mobile.runtime.RuntimeActorContext
import com.agentweave.mobile.runtime.RuntimeApprovalClient
import com.agentweave.mobile.runtime.RuntimeClient
import com.agentweave.mobile.runtime.RuntimeDiagnostics
import com.agentweave.mobile.runtime.RuntimeSkillPolicy
import com.agentweave.mobile.runtime.RuntimeSkillRollbackOutcome
import com.agentweave.mobile.runtime.AndroidAgentAppAppearanceStore
import com.agentweave.mobile.runtime.AndroidAgentAppLocalizationStore
import com.agentweave.mobile.secrets.InMemoryModelSecretStore
import com.agentweave.mobile.ui.AppTab
import com.agentweave.mobile.ui.AppRoot
import com.agentweave.mobile.ui.AgentWeaveTheme
import com.agentweave.mobile.ui.RuntimeSettingsGate
import com.agentweave.mobile.ui.RuntimeTurnGate
import com.agentweave.mobile.ui.SkillAction
import com.agentweave.mobile.ui.SkillScreenMode
import com.agentweave.mobile.ui.skillAccessState
import java.io.File
import java.io.IOException
import java.nio.file.FileAlreadyExistsException
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test
import org.json.JSONObject

class MainActivityInstrumentedTest {
  @Test
  fun debugAcceptanceBuildAllowsLoopbackEvidenceServer() {
    assertTrue(NetworkSecurityPolicy.getInstance().isCleartextTrafficPermitted("127.0.0.1"))
  }

  @Test
  fun disabledAndOwnerPolicyStatesAreStableOnDevice() {
    val disabled = skillAccessState("disabled", emptySet())
    val owner = skillAccessState(
      "owner_only",
      setOf("inspect", "create_draft", "activate"),
    )

    assertFalse(AppTab.Skills in disabled.visibleTabs)
    assertEquals(SkillScreenMode.OwnerManage, owner.mode)
    assertTrue(SkillAction.Create in owner.actions)
    assertTrue(SkillAction.Activate in owner.actions)
    assertFalse(SkillAction.Delete in owner.actions)
  }

  @Test
  fun defaultApplicationLaunchesOnTheDevice() {
    val packageName = InstrumentationRegistry.getInstrumentation().targetContext.packageName
    assertEquals("com.agentweave.mobile", packageName)

    ActivityScenario.launch(MainActivity::class.java).use { scenario ->
      scenario.onActivity { activity ->
        assertTrue(activity.window.decorView.isShown)
      }
    }
  }

  @Test
  fun visualSkillManagementHarness() {
    val arguments = InstrumentationRegistry.getArguments()
    if (arguments.getString("visual_harness") != "true") return
    if (arguments.getString("real_runtime") == "true") {
      runRealRuntimeVisualHarness(arguments)
      return
    }
    val mode = arguments.getString("skill_mode") ?: "owner_only"
    val grants = if (mode == "owner_only") {
      setOf(
        "inspect",
        "create_draft",
        "edit_draft",
        "validate",
        "activate",
        "disable",
        "rollback",
        "delete_managed",
      )
    } else {
      emptySet()
    }
    val diagnostics = visualDiagnostics(mode)
    val native = VisualNativeRuntime(
      mode = mode,
      failInitialLoad = arguments.getString("skill_initial_error") == "true",
      failSynchronization = arguments.getString("skill_sync_warning") == "true",
    )
    val policy = RuntimeSkillPolicy(
      mode = mode,
      agentAuthoring = mode == "owner_only",
      allowedKinds = arguments.getString("skill_allowed_kinds")
        ?.split(',')
        ?.filter(String::isNotBlank)
        ?: listOf("instruction_only", "host_tools_only"),
    )
    val client = RuntimeClient(
      handle = 77L,
      native = native,
      skillGrants = grants,
      actorContext = RuntimeActorContext("android-requester", "owner", grants = grants.toList()),
      skillPolicy = policy,
      approverClient = RuntimeApprovalClient(
        78L,
        native,
        RuntimeActorContext(
          "android-approver",
          "owner",
          grants = listOf("activate", "rollback", "delete_managed", "override_builtin"),
        ),
        policy,
      ),
    )
    val turnGate = RuntimeTurnGate()
    val settingsGate = RuntimeSettingsGate()

    ActivityScenario.launch(MainActivity::class.java).use { scenario ->
      scenario.onActivity { activity ->
        val appearance = AndroidAgentAppAppearanceStore(activity).appearance
        val localization = AndroidAgentAppLocalizationStore(activity).localization
        activity.setContent {
          AgentWeaveTheme {
            AppRoot(
              runtimeClient = client,
              turnGate = turnGate,
              settingsGate = settingsGate,
              initialDiagnostics = diagnostics,
              secretStore = InMemoryModelSecretStore(),
              appearance = appearance,
              selectedThemeId = appearance.defaultTheme,
              localization = localization,
              selectedLocaleId = localization.defaultLocale,
              onThemeSelected = {},
              onLocaleSelected = {},
              modifier = Modifier.safeDrawingPadding(),
            )
          }
        }
      }
      Thread.sleep(arguments.getString("visual_wait_ms")?.toLongOrNull() ?: 240_000L)
    }
    turnGate.close()
    settingsGate.close()
    client.close()
  }

  @Test
  fun authoritativeNativeLifecycleTransitionsOnDevice() {
    runAuthoritativeNativeLifecycleTransitions()
  }

  @Test
  fun nextTurnEvidenceRequiresInstructionCaptureAndAuthoritativeRuntimeBinding() {
    val userText = "task17-mobile prove_active_skill nonce:nonce-absolute-1"
    val requestBody = JSONObject()
      .put(
        "input",
        org.json.JSONArray()
          .put(
            JSONObject()
              .put("role", "developer")
              .put(
                "content",
                "<skill_instructions name=\"Task17 mobile lifecycle\" source=\"SKILL.md\">" +
                  "TASK17_UI_ACTIVE_SKILL_EVIDENCE</skill_instructions>",
              ),
          )
          .put(JSONObject().put("role", "user").put("content", userText)),
      )
    val hostCapture = JSONObject()
      .put("request_id", "request-1")
      .put("capture_nonce", "nonce-absolute-1")
      .put("user_text", userText)
      .put("marker", "TASK17_UI_ACTIVE_SKILL_EVIDENCE")
      .put("marker_location", "skill_instructions")
      .put("raw_request_sha256", "a".repeat(64))
      .put("request_body", requestBody)
    val authoritative = JSONObject()
      .put("source", "mobile_runtime_ffi")
      .put("package_id", "com.example.task17-mobile")
      .put("active_revision_id", "revision-1")
      .put("content_hash", "hash-1")
    val evidence = JSONObject(hostCapture.toString())
      .put("active_revision_id", "revision-1")
      .put("content_hash", "hash-1")
      .put("authoritative_before", authoritative)
      .put(
        "authoritative_after",
        JSONObject(authoritative.toString()),
      )

    assertTrue(
      validateNextTurnEvidence(
        evidence,
        hostCapture,
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertFalse(
      validateNextTurnEvidence(
        JSONObject(evidence.toString()).put("active_revision_id", "revision-2"),
        hostCapture,
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertFalse(
      validateNextTurnEvidence(
        JSONObject(evidence.toString()).put("marker_location", "available_skills"),
        hostCapture,
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertFalse(
      validateNextTurnEvidence(
        JSONObject(evidence.toString()).put("raw_request_sha256", "forged-header-value"),
        hostCapture,
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertFalse(
      validateNextTurnEvidence(
        JSONObject(evidence.toString()).put("request_id", "stale-request"),
        hostCapture,
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertFalse(
      validateNextTurnEvidence(
        evidence,
        JSONObject(hostCapture.toString()).put("capture_nonce", "reused-nonce"),
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertFalse(
      validateNextTurnEvidence(
        evidence,
        JSONObject(hostCapture.toString()).put("request_body", JSONObject()),
        expectedNonce = "nonce-absolute-1",
        expectedUserText = userText,
        expectedRevisionId = "revision-1",
        expectedContentHash = "hash-1",
      ),
    )
    assertTrue(secureAcceptanceNonce() != secureAcceptanceNonce())

    for (extra in listOf(
      "<available_skills>TASK17_UI_ACTIVE_SKILL_EVIDENCE</available_skills>",
      "<skill_instructions name=\"another-skill\">TASK17_UI_ACTIVE_SKILL_EVIDENCE</skill_instructions>",
      "ordinary developer text TASK17_UI_ACTIVE_SKILL_EVIDENCE",
    )) {
      val duplicateBody = JSONObject(requestBody.toString())
      val developer = duplicateBody.getJSONArray("input").getJSONObject(0)
      developer.put("content", "${developer.getString("content")}\n$extra")
      val duplicateHost = JSONObject(hostCapture.toString()).put("request_body", duplicateBody)
      val duplicateEvidence = JSONObject(evidence.toString()).put("request_body", duplicateBody)
      assertFalse(
        validateNextTurnEvidence(
          duplicateEvidence,
          duplicateHost,
          expectedNonce = "nonce-absolute-1",
          expectedUserText = userText,
          expectedRevisionId = "revision-1",
          expectedContentHash = "hash-1",
        ),
      )
    }
  }

  @Test
  fun evidenceCreateNewRejectsExistingTargetAndCleansTemporary() {
    val root = File(
      InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
      "task17-create-new-${UUID.randomUUID()}",
    ).apply { mkdirs() }
    val target = File(root, "evidence.json").apply { writeText("foreign") }

    try {
      assertThrows(FileAlreadyExistsException::class.java) {
        writeJsonCreateNew(target, JSONObject().put("request_id", "new"))
      }
      assertEquals("foreign", target.readText())
      assertEquals(listOf("evidence.json"), root.list()?.sorted())
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun evidenceCreateNewCleansTemporaryWhenSyncFailsBeforeLink() {
    val root = File(
      InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
      "task17-create-new-sync-${UUID.randomUUID()}",
    ).apply { mkdirs() }
    val target = File(root, "evidence.json")

    try {
      assertThrows(IOException::class.java) {
        writeJsonCreateNew(target, JSONObject().put("request_id", "new")) {
          throw IOException("injected pre-link sync failure")
        }
      }
      assertFalse(target.exists())
      assertTrue(root.list()?.isEmpty() == true)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun distinctActorsApproveActivationRollbackAndRemoval() {
    val native = VisualNativeRuntime("owner_only")
    val actor = RuntimeActorContext("android-requester", "owner", grants = listOf("inspect", "activate"))
    val policy = RuntimeSkillPolicy(
      mode = "owner_only",
      allowedKinds = listOf("instruction_only", "host_tools_only"),
    )
    val client = RuntimeClient(
      handle = 77L,
      native = native,
      actorContext = actor,
      skillPolicy = policy,
      approverClient = RuntimeApprovalClient(
        78L,
        native,
        RuntimeActorContext(
          "android-approver",
          "owner",
          grants = listOf("activate", "rollback", "delete_managed"),
        ),
        policy,
      ),
    )

    val activation = client.requestSkillActivation("revision-draft")
    client.resolveSkillApproval(activation.approvalId, true)
    val rollback = client.rollbackManagedSkill("com.agentweave.research", "revision-old")
      as RuntimeSkillRollbackOutcome.ApprovalRequired
    client.resolveSkillApproval(rollback.approval.approvalId, true)
    val removal = client.requestSkillRemoval("com.agentweave.research")
    client.resolveSkillApproval(removal.approvalId, true)

    assertEquals(listOf(78L, 78L, 78L), native.calls.filter { it.second == "resolve_skill_approval" }.map { it.first })
    val selfResponse = native.invoke(
      77L,
      """{"operation":"resolve_skill_approval","approval_id":"self","approve":true}""",
    )
    assertTrue(selfResponse.contains("self-approval is forbidden"))
    client.close()
  }
}

private fun visualDiagnostics(mode: String) = RuntimeDiagnostics(
  platform = "android",
  capabilities = listOf(
    "network.http",
    "filesystem.app_data",
    "secure_storage",
    "model.http_provider",
  ),
  databaseReady = true,
  skillsReady = true,
  modelConfigured = false,
  skillManagementMode = mode,
  activeSnapshotGeneration = 7,
  quarantinedCount = 0,
  lastReloadStatus = "generation:7",
)

private class VisualNativeRuntime(
  private val mode: String,
  private val failInitialLoad: Boolean = false,
  private val failSynchronization: Boolean = false,
) : NativeRuntimeApi {
  private var validationCount = 0
  private var initialLoadFailed = false
  private var activated = false
  private var synchronizationFailed = false
  private var savedInstructions = "Summarize trusted sources and cite every factual claim."
  private var pendingOperation: String? = null
  val calls = mutableListOf<Pair<Long, String>>()

  override fun initialize(requestJson: String): String = error("not used")

  override fun invoke(handle: Long, requestJson: String): String {
    val request = JSONObject(requestJson)
    val operation = request.getString("operation")
    calls += handle to operation
    if (operation == "resolve_skill_approval" && handle == 77L) {
      return """{"ok":false,"error":{"code":"runtime_error","message":"self-approval is forbidden"}}"""
    }
    if (operation == "list_skills" && failInitialLoad && !initialLoadFailed) {
      initialLoadFailed = true
      return """{"ok":false,"error":{"code":"runtime_error","message":"Managed inventory unavailable"}}"""
    }
    if (operation == "synchronize_skills" && failSynchronization && !synchronizationFailed) {
      synchronizationFailed = true
      return """{"ok":false,"error":{"code":"runtime_error","message":"requester synchronization failed"}}"""
    }
    if (operation == "update_skill_draft") {
      val files = request.getJSONArray("files")
      repeat(files.length()) { index ->
        val file = files.getJSONObject(index)
        if (file.getString("path") == "SKILL.md") savedInstructions = file.getString("content")
      }
    }
    val data = when (operation) {
      "diagnostics" -> diagnosticsJson()
      "list_skills" -> skillInventoryJson()
      "list_managed_skills" -> if (mode == "owner_only") managedInventoryJson() else "[]"
      "get_skill_detail" -> detailJson(request.getString("package_id"))
      "create_skill_draft", "update_skill_draft" -> draftSummaryJson()
      "validate_skill_draft" -> validationJson(++validationCount > 1)
      "request_skill_activation", "request_skill_removal" -> approvalJson(operation, request)
      "resolve_skill_approval" -> resolveApproval()
      "synchronize_skills" -> diagnosticsJson()
      "disable_managed_skill" -> reloadJson()
      "rollback_managed_skill" -> rollbackApprovalJson(request)
      "list_sessions" -> "[]"
      "create_session" -> sessionJson(request.optString("title", "New chat"))
      "get_messages" -> "[]"
      "load_model_config" -> "null"
      "save_model_config", "delete_session" -> "null"
      else -> error("unexpected visual operation: ${request.getString("operation")}")
    }
    return """{"ok":true,"data":$data}"""
  }

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
    """{"ok":true,"data":{"assistant_text":"Visual fixture reply"}}"""

  override fun close(handle: Long): String = """{"ok":true,"data":null}"""

  private fun diagnosticsJson(): String =
    """{"platform":"android","capabilities":["network.http","filesystem.app_data","secure_storage","model.http_provider"],"database_ready":true,"skills_ready":true,"model_configured":false,"skill_management_mode":"$mode","active_snapshot_generation":7,"quarantined_count":0,"last_reload_status":"generation:7"}"""

  private fun skillInventoryJson(): String = """[
    {"package_id":"com.agentweave.research","display_name":"Research assistant","version":"${if (activated) "1.5.0" else "1.4.0"}","source_layer":"managed","status":"active","available":true,"reason":"","active_revision_id":"${if (activated) "b71c6c72-8893-49f4-b593-111111111111" else "8a41912f-a83c-4fd8-a3b4-123456789abc"}","manageable":true},
    {"package_id":"com.agentweave.calendar","display_name":"Calendar briefing","version":"1.0.0","source_layer":"builtin","status":"capability_missing","available":false,"reason":"Missing required capability: calendar.read","active_revision_id":null,"manageable":false},
    {"package_id":"com.agentweave.notes","display_name":"Meeting notes","version":"2.1.0","source_layer":"builtin","status":"active","available":true,"reason":"","active_revision_id":null,"manageable":false}
  ]"""

  private fun managedInventoryJson(): String = """[
    {"package_id":"com.agentweave.research","display_name":"Research assistant","version":"${if (activated) "1.5.0" else "1.4.0"}","source_layer":"managed","status":"active","reason":"","active_revision_id":"${if (activated) "b71c6c72-8893-49f4-b593-111111111111" else "8a41912f-a83c-4fd8-a3b4-123456789abc"}","manageable":true}
  ]"""

  private fun detailJson(packageId: String): String {
    if (packageId != "com.agentweave.research") {
      return """{"package_id":"$packageId","display_name":"Built-in package","version":"1.0.0","source_layer":"builtin","status":"active","reason":"","active_revision_id":null,"revisions":[],"editable_draft":null}"""
    }
    val draft = revisionJson(
      id = "b71c6c72-8893-49f4-b593-111111111111",
      version = "1.5.0",
      status = if (activated) "managed" else "staging",
      editable = !activated,
      instructions = savedInstructions,
      valid = activated,
    )
    val active = revisionJson(
      id = "8a41912f-a83c-4fd8-a3b4-123456789abc",
      version = "1.4.0",
      status = "managed",
      editable = false,
      instructions = "Research a topic using approved host tools.",
      valid = true,
    )
    val old = revisionJson(
      id = "32af842d-e04d-49a1-a1b5-222222222222",
      version = "1.3.0",
      status = "managed",
      editable = false,
      instructions = "Research and summarize.",
      valid = true,
    )
    return """{"package_id":"com.agentweave.research","display_name":"Research assistant","version":"${if (activated) "1.5.0" else "1.4.0"}","source_layer":"managed","status":"active","reason":"","active_revision_id":"${if (activated) "b71c6c72-8893-49f4-b593-111111111111" else "8a41912f-a83c-4fd8-a3b4-123456789abc"}","revisions":[$draft,$active,$old],"editable_draft":${if (activated) "null" else draft}}"""
  }

  private fun revisionJson(
    id: String,
    version: String,
    status: String,
    editable: Boolean,
    instructions: String,
    valid: Boolean,
  ): String = """{"revision_id":"$id","version":"$version","status":"$status","editable":$editable,"created_by":"android-owner","created_at":"2026-07-13T09:30:00Z","kind":"host_tools_only","instructions":"$instructions","validation":{"ok":$valid,"errors":${if (valid) "[]" else "[\"Tool host/search is unavailable in this snapshot\"]"},"warnings":[]},"requirements":{"runtime_tools":["host/search","host/read"],"capabilities":["network.http","filesystem.app_data"],"connectors":[],"packages":[]},"permission_diff":{},"content_hash":"visual-detail-hash"}"""

  private fun draftSummaryJson(): String =
    """{"package_id":"com.agentweave.research","revision_id":"b71c6c72-8893-49f4-b593-111111111111","version":"1.5.0","kind":"host_tools_only","validation":{"status":"pending"},"status":"draft"}"""

  private fun validationJson(valid: Boolean): String =
    """{"ok":$valid,"errors":${if (valid) "[]" else "[\"Tool host/search is unavailable in this snapshot\"]"},"warnings":[],"requiredTools":["host/search","host/read"],"requiredConnectors":[],"dependencies":[],"requiredCapabilities":["network.http","filesystem.app_data"],"resolverStatus":"${if (valid) "active" else "capability_missing"}","resolverErrors":[],"permissionDiff":{"addedCapabilities":["network.http"],"removedCapabilities":[],"addedTools":[],"removedTools":[],"addedConnectors":[],"removedConnectors":[]},"revisionId":"b71c6c72-8893-49f4-b593-111111111111","contentHash":"visual-hash","snapshotGeneration":7}"""

  private fun approvalJson(operation: String, request: JSONObject): String {
    pendingOperation = operation
    val revision = request.optString("revision_id", "8a41912f-a83c-4fd8-a3b4-123456789abc")
    val diff = if (operation == "request_skill_activation") {
      """{"addedCapabilities":["network.http"],"removedCapabilities":[],"addedTools":[],"removedTools":[],"addedConnectors":[],"removedConnectors":[]}"""
    } else {
      "{}"
    }
    return """{"approval_id":"a9cb37b2-40d0-46d5-8fb2-333333333333","package_id":"com.agentweave.research","permission_diff":$diff,"requested_by":"android-requester","revision_id":"$revision","status":"pending"}"""
  }

  private fun rollbackApprovalJson(request: JSONObject): String {
    pendingOperation = "rollback_managed_skill"
    return """{"approval_id":"d83a3886-dffd-48f8-bd52-444444444444","package_id":"${request.getString("package_id")}","permission_diff":{},"requested_by":"android-requester","revision_id":"${request.getString("revision_id")}","status":"pending"}"""
  }

  private fun resolveApproval(): String {
    if (pendingOperation == "request_skill_activation") activated = true
    pendingOperation = null
    return reloadJson()
  }

  private fun reloadJson(): String =
    """{"previous_generation":7,"active_generation":8,"active_packages":2,"inactive_packages":1,"status":"approved"}"""

  private fun sessionJson(title: String): String =
    """{"id":"visual-session","title":"$title","created_at":"2026-07-13T09:00:00Z","updated_at":"2026-07-13T09:00:00Z"}"""
}

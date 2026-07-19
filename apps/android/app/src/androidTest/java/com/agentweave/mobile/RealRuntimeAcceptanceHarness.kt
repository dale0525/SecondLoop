package com.agentweave.mobile

import android.content.Context
import android.content.ContextWrapper
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.agentweave.mobile.runtime.RuntimeActorContext
import com.agentweave.mobile.runtime.RuntimeBridge
import com.agentweave.mobile.runtime.RuntimeClient
import com.agentweave.mobile.runtime.RuntimeModelConfig
import com.agentweave.mobile.runtime.AndroidAgentAppAppearanceStore
import com.agentweave.mobile.runtime.AndroidAgentAppLocalizationStore
import com.agentweave.mobile.runtime.RuntimeSkillDraftFile
import com.agentweave.mobile.runtime.RuntimeSkillDraftRequest
import com.agentweave.mobile.runtime.RuntimeSkillPolicy
import com.agentweave.mobile.runtime.RuntimeSkillRollbackOutcome
import com.agentweave.mobile.secrets.InMemoryModelSecretStore
import com.agentweave.mobile.ui.AppRoot
import com.agentweave.mobile.ui.AgentWeaveTheme
import com.agentweave.mobile.ui.RuntimeSettingsGate
import com.agentweave.mobile.ui.RuntimeTurnGate
import com.agentweave.mobile.ui.ownerSkillInventory
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.security.MessageDigest
import java.security.SecureRandom
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue

private const val LIFECYCLE_PACKAGE = "com.example.task17-mobile"
private const val RETAINED_PACKAGE = "com.example.task17-retained"
private const val ACTIVE_INSTRUCTION = "TASK17_UI_ACTIVE_SKILL_EVIDENCE"
private const val NEXT_TURN_PROMPT = "task17-mobile prove_active_skill"

private data class NextTurnBinding(
  val nonce: String,
  val userText: String,
  val revisionId: String,
  val contentHash: String,
)

internal fun runAuthoritativeNativeLifecycleTransitions() {
  val target = InstrumentationRegistry.getInstrumentation().targetContext
  val root = File(target.cacheDir, "native-lifecycle-${UUID.randomUUID()}")
  val context = IsolatedRuntimeContext(target, root)
  val client = runtimeBridge(context).load()
  try {
    val revisions = seedLifecycle(client)
    assertEquals(revisions.second, activeRevision(client, LIFECYCLE_PACKAGE))

    val rollback = client.rollbackManagedSkill(LIFECYCLE_PACKAGE, revisions.first)
      as RuntimeSkillRollbackOutcome.ApprovalRequired
    client.resolveSkillApproval(rollback.approval.approvalId, true)
    assertEquals(revisions.first, activeRevision(client, LIFECYCLE_PACKAGE))

    client.disableManagedSkill(LIFECYCLE_PACKAGE)
    assertEquals("disabled", managedStatus(client, LIFECYCLE_PACKAGE))
    assertFalse(client.listSkills().any { it.packageId == LIFECYCLE_PACKAGE && it.available })

    assertTrue(client.validateSkillDraft(revisions.third).ok)
    val reactivation = client.requestSkillActivation(revisions.third)
    client.resolveSkillApproval(reactivation.approvalId, true)
    assertEquals(revisions.third, activeRevision(client, LIFECYCLE_PACKAGE))

    val removal = client.requestSkillRemoval(LIFECYCLE_PACKAGE)
    client.resolveSkillApproval(removal.approvalId, true)
    val inventory = ownerSkillInventory(client.listSkills(), client.listManagedSkills())
    assertFalse(inventory.any { it.packageId == LIFECYCLE_PACKAGE })
  } finally {
    client.close()
    root.deleteRecursively()
  }
}

internal fun runRealRuntimeVisualHarness(arguments: Bundle) {
  val context = InstrumentationRegistry.getInstrumentation().targetContext
  val bridge = runtimeBridge(context)
  val client = bridge.load()
  val phase = arguments.getString("acceptance_phase") ?: "manual"
  val evidenceRoot = context.getExternalFilesDir(null) ?: context.filesDir
  val evidenceTarget = File(evidenceRoot, "task17-$phase-next-turn-evidence.json")
  val inputTarget = File(evidenceRoot, "task17-$phase-next-turn-input.json")
  val verifyNextTurn = arguments.getString("verify_next_turn") == "true"
  try {
    if (arguments.getString("seed_runtime") != "false") {
      seedLifecycle(client)
      seedRetained(client)
    }
    val secrets = InMemoryModelSecretStore()
    var nextTurnBinding: NextTurnBinding? = null
    var mockBaseUrl: String? = null
    arguments.getString("mock_base_url")?.let { baseUrl ->
      mockBaseUrl = baseUrl
      val nonce = secureAcceptanceNonce()
      val binding = authoritativeNextTurnBinding(client, nonce)
      nextTurnBinding = binding
      val secretId = "task17.mobile.mock"
      secrets.saveSecret(secretId, "task17-test-key")
      client.saveModelConfig(
        RuntimeModelConfig(
          providerId = "task17-mock",
          providerName = "Task17 mock",
          endpointType = "responses",
          baseUrl = baseUrl,
          modelName = "task17-model",
          secretId = secretId,
        ),
      )
      if (verifyNextTurn) {
        clearCaptureTarget(evidenceTarget)
        clearCaptureTarget(inputTarget)
        writeJsonCreateNew(
          inputTarget,
          JSONObject().put("capture_nonce", nonce).put("user_text", binding.userText),
        )
      }
    }
    val preexistingMessageIds = messageIds(client)
    writeAcceptanceState(context, client, "$phase-before")
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
              initialDiagnostics = client.diagnostics(),
              secretStore = secrets,
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
    writeAcceptanceState(context, client, "$phase-after")
    if (verifyNextTurn) {
      val binding = requireNotNull(nextTurnBinding) { "next-turn verification requires mock_base_url" }
      val hostCapture = fetchHostCapture(requireNotNull(mockBaseUrl), binding.nonce)
      val capture = capturedNextTurnEvidence(client, binding.userText, preexistingMessageIds)
      val evidence = bindAuthoritativeRuntimeState(capture, hostCapture, binding, client)
      assertTrue(
        evidence.toString(2),
        validateNextTurnEvidence(
          evidence,
          hostCapture,
          expectedNonce = binding.nonce,
          expectedUserText = binding.userText,
          expectedRevisionId = binding.revisionId,
          expectedContentHash = binding.contentHash,
        ),
      )
      writeJsonCreateNew(evidenceTarget, evidence)
    }
    turnGate.close()
    settingsGate.close()
  } finally {
    client.close()
  }
}

private fun runtimeBridge(context: Context): RuntimeBridge {
  val grants = listOf(
    "inspect",
    "create_draft",
    "edit_draft",
    "validate",
    "activate",
    "disable",
    "rollback",
    "delete_managed",
  )
  val policy = RuntimeSkillPolicy(
    mode = "owner_only",
    agentAuthoring = true,
    allowedKinds = listOf("instruction_only", "host_tools_only"),
    rollbackApprovalRequired = true,
  )
  return RuntimeBridge(
    context = context,
    configuredSkillPolicy = policy,
    configuredActorContext = RuntimeActorContext(
      actorId = "android-requester",
      role = "owner",
      grants = grants,
    ),
    configuredApproverContext = RuntimeActorContext(
      actorId = "android-approver",
      role = "owner",
      grants = listOf("activate", "rollback", "delete_managed", "override_builtin"),
    ),
  )
}

private fun seedLifecycle(client: RuntimeClient): Triple<String, String, String> {
  val existing = client.listManagedSkills().find { it.packageId == LIFECYCLE_PACKAGE }
  if (existing != null) {
    val revisions = client.getSkillDetail(LIFECYCLE_PACKAGE).revisions
    val immutable = revisions.filter { !it.editable }.sortedBy { it.version }
    val draft = revisions.single { it.editable }
    return Triple(immutable.first().revisionId, immutable.last().revisionId, draft.revisionId)
  }
  val first = createValidatedDraft(client, LIFECYCLE_PACKAGE, "1.0.0", "Initial mobile instructions")
  activate(client, first)
  val second = createValidatedDraft(client, LIFECYCLE_PACKAGE, "2.0.0", ACTIVE_INSTRUCTION)
  activate(client, second)
  val draft = createValidatedDraft(client, LIFECYCLE_PACKAGE, "3.0.0", "Reactivated mobile instructions")
  return Triple(first, second, draft)
}

private fun seedRetained(client: RuntimeClient): String {
  client.listManagedSkills().find { it.packageId == RETAINED_PACKAGE }?.activeRevisionId?.let {
    return it
  }
  val revision = createValidatedDraft(client, RETAINED_PACKAGE, "1.0.0", "Retained managed instructions")
  activate(client, revision)
  return revision
}

private fun createValidatedDraft(
  client: RuntimeClient,
  packageId: String,
  version: String,
  instructions: String,
): String {
  val displayName = if (packageId == LIFECYCLE_PACKAGE) "Task17 mobile lifecycle" else "Task17 retained"
  val description = "Task17 Android acceptance package without instruction marker"
  val aliases = if (packageId == LIFECYCLE_PACKAGE) "aliases:\n  - task17-mobile\n" else ""
  val draft = client.createSkillDraft(
    RuntimeSkillDraftRequest(
      packageId = packageId,
      displayName = displayName,
      description = description,
      kind = "instruction_only",
      requiredTools = emptyList(),
      initialFiles = listOf(
        RuntimeSkillDraftFile(
          "SKILL.md",
          "---\nname: $displayName\ndescription: $description.\n$aliases---\n\n$instructions",
        ),
        RuntimeSkillDraftFile("agentweave.json", descriptor(packageId, displayName, version)),
      ),
    ),
  )
  val validation = client.validateSkillDraft(draft.revisionId)
  assertTrue(validation.errors.joinToString(), validation.ok)
  return draft.revisionId
}

private fun activate(client: RuntimeClient, revisionId: String) {
  val approval = client.requestSkillActivation(revisionId)
  client.resolveSkillApproval(approval.approvalId, true)
}

private fun descriptor(packageId: String, displayName: String, version: String): String =
  JSONObject()
    .put("schemaVersion", 1)
    .put("id", packageId)
    .put("version", version)
    .put("displayName", displayName)
    .put("kind", "instruction_only")
    .put("package", JSONObject().put("includeInstructions", true).put("includeRuntime", false))
    .put("compatibility", JSONObject().put("minimumRuntimeVersion", JSONObject.NULL).put("platforms", JSONArray()))
    .put(
      "requires",
      JSONObject()
        .put("packages", JSONArray())
        .put("capabilities", JSONArray())
        .put("runtimeTools", JSONArray())
        .put("connectors", JSONArray()),
    )
    .toString(2)

private fun activeRevision(client: RuntimeClient, packageId: String): String? =
  client.listManagedSkills().find { it.packageId == packageId }?.activeRevisionId

private fun managedStatus(client: RuntimeClient, packageId: String): String? =
  client.listManagedSkills().find { it.packageId == packageId }?.status

private fun authoritativeNextTurnBinding(client: RuntimeClient, nonce: String): NextTurnBinding {
  val detail = client.getSkillDetail(LIFECYCLE_PACKAGE)
  val revisionId = requireNotNull(detail.activeRevisionId) { "lifecycle package has no active revision" }
  val revision = detail.revisions.single { it.revisionId == revisionId }
  check(revision.instructions.contains(ACTIVE_INSTRUCTION)) {
    "active lifecycle revision does not contain the acceptance marker"
  }
  check(revision.contentHash.isNotBlank()) { "active lifecycle revision has no content hash" }
  return NextTurnBinding(
    nonce = nonce,
    userText = "$NEXT_TURN_PROMPT nonce:$nonce",
    revisionId = revisionId,
    contentHash = revision.contentHash,
  )
}

private fun messageIds(client: RuntimeClient): Set<String> = client.listSessions()
  .flatMap { session -> client.getMessages(session.id) }
  .mapTo(mutableSetOf()) { message -> message.id }

private fun capturedNextTurnEvidence(
  client: RuntimeClient,
  expectedUserText: String,
  preexistingMessageIds: Set<String>,
): JSONObject {
  val artifact = client.listSessions()
    .asSequence()
    .flatMap { session -> client.getMessages(session.id).asSequence() }
    .filter { message -> message.role == "assistant" && message.id !in preexistingMessageIds }
    .mapNotNull { message -> runCatching { JSONObject(message.content) }.getOrNull() }
    .lastOrNull { evidence -> evidence.optString("user_text") == expectedUserText }
  return requireNotNull(artifact) { "UI-triggered next-turn evidence was not persisted" }
}

private fun bindAuthoritativeRuntimeState(
  capture: JSONObject,
  hostCapture: JSONObject,
  binding: NextTurnBinding,
  client: RuntimeClient,
): JSONObject {
  check(capturesMatch(capture, hostCapture)) { "persisted response differs from host capture" }
  val current = authoritativeNextTurnBinding(client, binding.nonce)
  check(current.revisionId == binding.revisionId && current.contentHash == binding.contentHash) {
    "active lifecycle revision changed during the UI provider request"
  }
  return JSONObject(capture.toString())
    .put("active_revision_id", binding.revisionId)
    .put("content_hash", binding.contentHash)
    .put(
      "authoritative_before",
      authoritativeState(binding.revisionId, binding.contentHash),
    )
    .put(
      "authoritative_after",
      authoritativeState(current.revisionId, current.contentHash),
    )
}

private fun authoritativeState(revisionId: String, contentHash: String): JSONObject = JSONObject()
  .put("source", "mobile_runtime_ffi")
  .put("package_id", LIFECYCLE_PACKAGE)
  .put("active_revision_id", revisionId)
  .put("content_hash", contentHash)

internal fun validateNextTurnEvidence(
  evidence: JSONObject,
  hostCapture: JSONObject,
  expectedNonce: String,
  expectedUserText: String,
  expectedRevisionId: String,
  expectedContentHash: String,
): Boolean {
  val marker = evidence.optString("marker")
  val developerText = requestContentForRole(evidence.optJSONObject("request_body"), "developer")
  val requestBody = evidence.optJSONObject("request_body") ?: return false
  val userBound = requestBody.optJSONArray("input")
    ?.let { input ->
      (0 until input.length()).any { index ->
        input.optJSONObject(index)?.let { item ->
          item.optString("role") == "user" && requestContentContains(item.opt("content"), expectedUserText)
        } == true
      }
    } == true
  val selectedMarkerCount = Regex(
    """<skill_instructions\s+[^>]*name="Task17 mobile lifecycle"[^>]*>([\s\S]*?)</skill_instructions>""",
  ).findAll(developerText).sumOf { match -> markerOccurrences(match.groupValues[1]) }
  val before = evidence.optJSONObject("authoritative_before") ?: return false
  val after = evidence.optJSONObject("authoritative_after") ?: return false
  return evidence.optString("request_id").isNotBlank() &&
    capturesMatch(evidence, hostCapture) &&
    hostCapture.optString("capture_nonce") == expectedNonce &&
    evidence.optString("capture_nonce") == expectedNonce &&
    evidence.optString("user_text") == expectedUserText &&
    evidence.optString("active_revision_id") == expectedRevisionId &&
    expectedContentHash.isNotBlank() &&
    evidence.optString("content_hash") == expectedContentHash &&
    marker == ACTIVE_INSTRUCTION &&
    evidence.optString("marker_location") == "skill_instructions" &&
    evidence.optString("raw_request_sha256").matches(Regex("[0-9a-f]{64}")) &&
    selectedMarkerCount > 0 &&
    markerOccurrences(developerText) == selectedMarkerCount &&
    authoritativeStateMatches(before, expectedRevisionId, expectedContentHash) &&
    authoritativeStateMatches(after, expectedRevisionId, expectedContentHash) &&
    userBound
}

private fun markerOccurrences(text: String): Int {
  var count = 0
  var offset = 0
  while (true) {
    val match = text.indexOf(ACTIVE_INSTRUCTION, offset)
    if (match < 0) return count
    count += 1
    offset = match + ACTIVE_INSTRUCTION.length
  }
}

private fun capturesMatch(left: JSONObject, right: JSONObject): Boolean =
  left.optString("request_id").isNotBlank() &&
    left.optString("request_id") == right.optString("request_id") &&
    left.optString("capture_nonce") == right.optString("capture_nonce") &&
    left.optString("user_text") == right.optString("user_text") &&
    left.optString("raw_request_sha256") == right.optString("raw_request_sha256") &&
    left.optJSONObject("request_body")?.toString() == right.optJSONObject("request_body")?.toString()

private fun authoritativeStateMatches(state: JSONObject, revisionId: String, contentHash: String): Boolean =
  state.optString("source") == "mobile_runtime_ffi" &&
    state.optString("package_id") == LIFECYCLE_PACKAGE &&
    state.optString("active_revision_id") == revisionId &&
    state.optString("content_hash") == contentHash

private fun requestContentForRole(requestBody: JSONObject?, role: String): String {
  val input = requestBody?.optJSONArray("input") ?: return ""
  return (0 until input.length()).mapNotNull { index ->
    input.optJSONObject(index)?.takeIf { it.optString("role") == role }?.opt("content")
  }.flatMap { content ->
    when (content) {
      is String -> listOf(content)
      is JSONArray -> (0 until content.length()).mapNotNull { index ->
        content.optJSONObject(index)
          ?.takeIf { it.optString("type") == "input_text" }
          ?.optString("text")
      }
      else -> emptyList()
    }
  }.joinToString("\n")
}

private fun requestContentContains(content: Any?, expected: String): Boolean {
  if (content == expected) return true
  val parts = content as? JSONArray ?: return false
  return (0 until parts.length()).any { index ->
    parts.optJSONObject(index)?.let { part ->
      part.optString("type") == "input_text" && part.optString("text") == expected
    } == true
  }
}

internal fun secureAcceptanceNonce(): String {
  val bytes = ByteArray(24)
  SecureRandom().nextBytes(bytes)
  return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}

private fun fetchHostCapture(baseUrl: String, nonce: String): JSONObject {
  val connection = URL(URL(baseUrl), "/task17-capture?nonce=$nonce")
    .openConnection() as HttpURLConnection
  connection.requestMethod = "GET"
  connection.connectTimeout = 10_000
  connection.readTimeout = 10_000
  try {
    check(connection.responseCode == 200) { "independent host capture is unavailable" }
    val bytes = connection.inputStream.use { input -> input.readNBytes(1_048_577) }
    check(bytes.size <= 1_048_576) { "independent host capture exceeds limit" }
    return JSONObject(String(bytes, StandardCharsets.UTF_8))
  } finally {
    connection.disconnect()
  }
}

private fun clearCaptureTarget(target: File) {
  check(!target.exists() || target.delete()) { "stale acceptance capture could not be cleared" }
}

internal fun writeJsonCreateNew(
  target: File,
  value: JSONObject,
  syncTemporary: (FileOutputStream) -> Unit = { output -> output.fd.sync() },
) {
  target.parentFile?.mkdirs()
  val temporary = File(target.parentFile, ".${target.name}.${UUID.randomUUID()}.tmp")
  Files.createFile(temporary.toPath())
  try {
    FileOutputStream(temporary).use { output ->
      output.write(value.toString(2).toByteArray(StandardCharsets.UTF_8))
      syncTemporary(output)
    }
    Files.createLink(target.toPath(), temporary.toPath())
  } finally {
    Files.deleteIfExists(temporary.toPath())
  }
}

private fun writeAcceptanceState(context: Context, client: RuntimeClient, phase: String) {
  val managed = client.listManagedSkills()
  val root = context.getExternalFilesDir(null) ?: context.filesDir
  val init = runtimeBridge(context).initRequest()
  val lock = File(init.builtinSkillsDir)
    .walkTopDown()
    .firstOrNull { file -> file.name == "skill-bundle.lock" && file.isFile }
  val state = JSONObject()
    .put("phase", phase)
    .put("bundle_lock_sha256", lock?.let(::sha256) ?: JSONObject.NULL)
    .put(
      "managed",
      JSONArray(managed.map { skill ->
        JSONObject()
          .put("package_id", skill.packageId)
          .put("status", skill.status)
          .put("version", skill.version)
          .put("active_revision_id", skill.activeRevisionId)
      }),
    )
  File(root, "task17-$phase.json").writeText(state.toString(2))
}

private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256")
  .digest(file.readBytes())
  .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

private class IsolatedRuntimeContext(base: Context, root: File) : ContextWrapper(base) {
  private val files = File(root, "files").apply { mkdirs() }
  private val cache = File(root, "cache").apply { mkdirs() }

  override fun getFilesDir(): File = files

  override fun getCacheDir(): File = cache
}

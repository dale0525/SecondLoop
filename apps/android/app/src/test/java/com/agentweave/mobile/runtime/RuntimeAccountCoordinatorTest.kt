package com.agentweave.mobile.runtime

import android.content.Context
import com.agentweave.mobile.secrets.InMemoryModelSecretStore
import com.agentweave.mobile.secrets.ModelSecretStore
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RuntimeAccountCoordinatorTest {
  @Test
  fun switchingAccountsStopsWorkClosesRuntimeAndRestoresOnlyMatchingState() {
    val context = RuntimeEnvironment.getApplication() as Context
    val events = mutableListOf<String>()
    val native = AccountSwitchNativeRuntime(events)
    val stores = linkedMapOf<String?, InMemoryModelSecretStore>()
    val coordinator = RuntimeAccountCoordinator(
      bridge = RuntimeBridge(
        context = context,
        native = native,
        skillAssets = AccountSkillAssets(),
        publicationFileSystem = JvmSkillPublicationFileSystem(),
      ),
      secretStoreForAccount = { accountId ->
        events += "secret:$accountId"
        stores.getOrPut(accountId, ::InMemoryModelSecretStore)
      },
      stopActiveWork = { events += "stop" },
    )
    val accountA = accountContext("account-a")
    val accountB = accountContext("account-b")
    val accountAId = accountA.scopedAccountId()
    val accountBId = accountB.scopedAccountId()
    assertEquals(
      "usr_e96830780c9c742d7043da4937a107ecc16cf37c7f834b13da72c8cb699030ed",
      accountAId,
    )

    val firstA = coordinator.start(accountA)
    firstA.client.createSession("Account A only")
    native.seedMemory(firstA.client.handle, "Memory A only")
    firstA.secretStore.saveSecret("model.$accountAId.openai.default", "sk-account-a")

    val sessionB = coordinator.switchAccount(accountB)
    assertEquals(emptyList<RuntimeSession>(), sessionB.client.listSessions())
    assertEquals(emptyList<RuntimeMemory>(), sessionB.client.listMemories())
    assertNull(sessionB.secretStore.loadSecret("model.$accountBId.openai.default"))
    sessionB.client.createSession("Account B only")
    native.seedMemory(sessionB.client.handle, "Memory B only")
    sessionB.secretStore.saveSecret("model.$accountBId.openai.default", "sk-account-b")

    val secondA = coordinator.switchAccount(accountA)
    assertEquals(listOf("Account A only"), secondA.client.listSessions().map { it.title })
    assertEquals(listOf("Memory A only"), secondA.client.listMemories().map { it.text })
    assertEquals(
      "sk-account-a",
      secondA.secretStore.loadSecret("model.$accountAId.openai.default"),
    )
    assertEquals(
      listOf(
        "secret:$accountAId",
        "initialize:account-a",
        "stop",
        "close:1",
        "secret:$accountBId",
        "initialize:account-b",
        "stop",
        "close:2",
        "secret:$accountAId",
        "initialize:account-a",
      ),
      events.filter { event ->
        event == "stop" ||
          event.startsWith("close:") ||
          event.startsWith("secret:") ||
          event.startsWith("initialize:")
      },
    )

    coordinator.close()
  }
}

private fun accountContext(subject: String): RuntimeSecurityContext =
  RuntimeSecurityContext(
    providerId = "agentweave.identity.oidc",
    appId = "com.example.mobile-managed",
    tenantId = "tenant-main",
    audience = "https://gateway.example.test",
    principal = RuntimePrincipalIdentity(
      issuer = "https://identity.example.test",
      subject = subject,
    ),
    grantedScopes = listOf("openid", "profile"),
    authenticatedAt = "2026-07-19T08:00:00Z",
    expiresAt = "2026-07-19T09:00:00Z",
  )

private class AccountSwitchNativeRuntime(
  private val events: MutableList<String>,
) : NativeRuntimeApi {
  private var nextHandle = 0L
  private val accountByHandle = linkedMapOf<Long, String>()
  private val accountIdByHandle = linkedMapOf<Long, String>()
  private val sessions = linkedMapOf<String, MutableList<JSONObject>>()
  private val memories = linkedMapOf<String, MutableList<JSONObject>>()

  override fun initialize(requestJson: String): String {
    val context = JSONObject(requestJson).getJSONObject("security_context")
    val principal = context.getJSONObject("principal")
    val subject = principal.getString("subject")
    val accountId = RuntimeSecurityContext(
      schemaVersion = context.getInt("schemaVersion"),
      providerId = context.getString("providerId"),
      appId = context.getString("appId"),
      tenantId = context.getString("tenantId"),
      audience = context.getString("audience"),
      principal = RuntimePrincipalIdentity(
        issuer = principal.getString("issuer"),
        subject = subject,
      ),
      grantedScopes = emptyList(),
      authenticatedAt = context.getString("authenticatedAt"),
      expiresAt = context.getString("expiresAt"),
    ).scopedAccountId()
    val handle = ++nextHandle
    accountByHandle[handle] = subject
    accountIdByHandle[handle] = accountId
    events += "initialize:$subject"
    return ok(JSONObject().put("handle", handle))
  }

  override fun invoke(handle: Long, requestJson: String): String {
    val subject = checkNotNull(accountByHandle[handle])
    val request = JSONObject(requestJson)
    val data: Any = when (request.getString("operation")) {
      "diagnostics" -> diagnostics(checkNotNull(accountIdByHandle[handle]))
      "create_session" -> JSONObject()
        .put("id", "${subject}-${sessions.getOrPut(subject, ::mutableListOf).size + 1}")
        .put("title", request.getString("title"))
        .put("created_at", "2026-07-19T08:00:00Z")
        .put("updated_at", "2026-07-19T08:00:00Z")
        .also { sessions.getValue(subject) += it }
      "list_sessions" -> JSONArray(sessions[subject].orEmpty())
      "list_memories" -> JSONArray(memories[subject].orEmpty())
      else -> error("unexpected operation: ${request.getString("operation")}")
    }
    return ok(data)
  }

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
    error("not used")

  override fun close(handle: Long): String {
    events += "close:$handle"
    accountByHandle.remove(handle)
    accountIdByHandle.remove(handle)
    return ok(JSONObject.NULL)
  }

  fun seedMemory(handle: Long, text: String) {
    val subject = checkNotNull(accountByHandle[handle])
    memories.getOrPut(subject, ::mutableListOf) += JSONObject()
      .put("id", "memory-$subject")
      .put("kind", "fact")
      .put("value", JSONObject().put("text", text).put("attributes", JSONObject()))
      .put("evidence", JSONArray())
      .put("confidence", 100)
      .put("sensitivity", "private")
      .put("retention", JSONObject().put("mode", "durable"))
      .put("state", "active")
      .put("version", 1)
      .put("updatedAt", "2026-07-19T08:00:00Z")
  }

  private fun diagnostics(accountId: String): JSONObject =
    JSONObject()
      .put("app_id", "com.example.mobile-managed")
      .put("app_version", "0.1.0")
      .put("app_display_name", "Managed Mobile")
      .put("platform", "android")
      .put("capabilities", JSONArray())
      .put("database_ready", true)
      .put("skills_ready", true)
      .put("model_configured", true)
      .put("model_configuration_policy", "app_managed")
      .put("identity_mode", "required")
      .put("account_id", accountId)
      .put("skill_management_mode", "disabled")
      .put("active_snapshot_generation", 1)
      .put("quarantined_count", 0)
      .put("last_reload_status", "ready")

  private fun ok(data: Any): String = JSONObject().put("ok", true).put("data", data).toString()
}

private class AccountSkillAssets : SkillAssetSource {
  private val files = mapOf(
    "current" to "current".toByteArray(StandardCharsets.UTF_8),
    "generations/current/skill-bundle.json" to "manifest".toByteArray(StandardCharsets.UTF_8),
    "generations/current/skill-bundle.lock" to "lock".toByteArray(StandardCharsets.UTF_8),
  )

  override fun bundleHash(): String {
    val digest = MessageDigest.getInstance("SHA-256")
    files.toSortedMap().forEach { (path, bytes) ->
      digest.update(path.toByteArray(StandardCharsets.UTF_8))
      digest.update(0)
      digest.update(bytes.size.toString().toByteArray(StandardCharsets.US_ASCII))
      digest.update(0)
      digest.update(bytes)
    }
    return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
  }

  override fun entries(): List<SkillAssetEntry> =
    files.keys.map { SkillAssetEntry(it, SkillAssetType.FILE) }

  override fun open(relativePath: String): InputStream =
    ByteArrayInputStream(checkNotNull(files[relativePath]))
}

package com.agentweave.mobile

import android.content.Context
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import com.agentweave.mobile.runtime.MobileIdentityAuthorizationStart
import com.agentweave.mobile.runtime.MobileIdentityBridgeException
import com.agentweave.mobile.runtime.MobileIdentityClient
import com.agentweave.mobile.runtime.MobileIdentityLogout
import com.agentweave.mobile.runtime.MobileIdentitySessionState
import com.agentweave.mobile.runtime.MobileIdentityStatus
import com.agentweave.mobile.runtime.NativeRuntimeApi
import com.agentweave.mobile.runtime.RuntimeBridge
import com.agentweave.mobile.runtime.RuntimeGatewayCredential
import com.agentweave.mobile.runtime.RuntimePrincipalIdentity
import com.agentweave.mobile.runtime.RuntimeSecurityContext
import com.agentweave.mobile.runtime.SkillAssetEntry
import com.agentweave.mobile.runtime.SkillAssetSource
import com.agentweave.mobile.runtime.SkillAssetType
import com.agentweave.mobile.runtime.JvmSkillPublicationFileSystem
import com.agentweave.mobile.runtime.scopedAccountId
import com.agentweave.mobile.secrets.InMemoryModelSecretStore
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RuntimeHostViewModelTest {
  @After
  fun resetDependencies() {
    RuntimeDependencies.reset()
  }

  @Test
  fun expiredSessionStopsBeforeNativeRuntimeInitialization() {
    val identity = FakeIdentityClient(expiredStatus("account-a"))
    val native = IdentityScopedNativeRuntime()
    val harness = harness(identity, native)
    try {
      val state = harness.awaitState<RuntimeHostState.AuthenticationRequired>()

      assertEquals(IdentityPromptPhase.Expired, state.phase)
      assertTrue(native.events.isEmpty())
    } finally {
      harness.close()
    }
  }

  @Test
  fun accountReloginClosesEachOldRuntimeBeforeActivatingTheNextAccount() {
    val identity = FakeIdentityClient(signedOutStatus())
    val native = IdentityScopedNativeRuntime()
    val harness = harness(identity, native)
    try {
      harness.awaitState<RuntimeHostState.AuthenticationRequired>()

      signIn(harness, identity, "account-a")
      signIn(harness, identity, "account-b")
      signIn(harness, identity, "account-a")

      assertEquals(
        listOf(
          "initialize:account-a",
          "close:1",
          "initialize:account-b",
          "close:2",
          "initialize:account-a",
        ),
        native.events,
      )
      assertEquals(listOf(false, true, true), identity.accountSelectionPrompts)
      val ready = harness.awaitState<RuntimeHostState.Ready>()
      assertEquals("account-a", ready.session.identityStatus?.securityContext?.principal?.subject)
    } finally {
      harness.close()
    }
  }

  @Test
  fun maliciousCallbackClosesOldAccountAndCannotActivateAnotherRuntime() {
    val identity = FakeIdentityClient(signedInStatus("account-a"))
    val native = IdentityScopedNativeRuntime()
    val harness = harness(identity, native)
    try {
      harness.awaitState<RuntimeHostState.Ready>()
      harness.viewModel.beginSignIn()
      harness.awaitPhase(IdentityPromptPhase.WaitingForBrowser)
      harness.viewModel.handleIdentityCallback("com.example.mobile:/oidc/callback?state=forged")
      val prompt = harness.awaitState<RuntimeHostState.AuthenticationRequired>() {
        it.phase == IdentityPromptPhase.Unavailable && it.errorMessage != null
      }

      assertEquals(IdentityPromptPhase.Unavailable, prompt.phase)
      assertEquals(listOf("initialize:account-a", "close:1"), native.events)
    } finally {
      harness.close()
    }
  }

  @Test
  fun duplicateCallbackIsIgnoredWithoutClosingTheAuthenticatedRuntime() {
    val identity = FakeIdentityClient(signedOutStatus())
    val native = IdentityScopedNativeRuntime()
    val harness = harness(identity, native)
    try {
      harness.awaitState<RuntimeHostState.AuthenticationRequired>()
      harness.viewModel.beginSignIn()
      harness.awaitPhase(IdentityPromptPhase.WaitingForBrowser)
      identity.nextStatus = signedInStatus("account-a")
      val callback = "com.example.mobile:/oidc/callback?code=account-a&state=valid"
      harness.viewModel.handleIdentityCallback(callback)
      harness.awaitState<RuntimeHostState.Ready>()

      harness.viewModel.handleIdentityCallback(callback)
      shadowOf(android.os.Looper.getMainLooper()).idle()

      assertTrue(harness.viewModel.state.value is RuntimeHostState.Ready)
      assertEquals(listOf("initialize:account-a"), native.events)
    } finally {
      harness.close()
    }
  }

  @Test
  fun clearingLocalDataSignsOutClosesRuntimeAndTargetsOnlyTheActiveAccount() {
    val identity = FakeIdentityClient(signedInStatus("account-a"))
    val native = IdentityScopedNativeRuntime()
    val cleared = mutableListOf<String>()
    val harness = harness(identity, native)
    RuntimeDependencies.accountDataStoreFactory = {
      com.agentweave.mobile.runtime.RuntimeAccountDataStore { account -> cleared += account }
    }
    try {
      val ready = harness.awaitState<RuntimeHostState.Ready>()
      val accountId = checkNotNull(ready.session.identityStatus?.accountId)

      harness.viewModel.clearAccountData()
      harness.awaitState<RuntimeHostState.AuthenticationRequired> {
        it.phase == IdentityPromptPhase.SignedOut
      }

      assertEquals(listOf(accountId), cleared)
      assertEquals(listOf("initialize:account-a", "close:1"), native.events)
    } finally {
      harness.close()
    }
  }

  private fun signIn(
    harness: ViewModelHarness,
    identity: FakeIdentityClient,
    subject: String,
  ) {
    harness.viewModel.beginSignIn()
    harness.awaitPhase(IdentityPromptPhase.WaitingForBrowser)
    identity.nextStatus = signedInStatus(subject)
    harness.viewModel.handleIdentityCallback(
      "com.example.mobile:/oidc/callback?code=$subject&state=valid-${identity.accountSelectionPrompts.size}",
    )
    harness.awaitState<RuntimeHostState.Ready> {
      it.session.identityStatus?.securityContext?.principal?.subject == subject
    }
  }

  private fun harness(
    identity: FakeIdentityClient,
    native: IdentityScopedNativeRuntime,
  ): ViewModelHarness {
    val context = RuntimeEnvironment.getApplication() as Context
    RuntimeDependencies.identityLoader = { identity }
    RuntimeDependencies.runtimeBridgeFactory = {
      RuntimeBridge(
        context = context,
        native = native,
        skillAssets = HostSkillAssets,
        publicationFileSystem = JvmSkillPublicationFileSystem(),
      )
    }
    RuntimeDependencies.modelSecretStoreFactory = { _, _ -> InMemoryModelSecretStore() }
    val owner = TestViewModelOwner()
    val viewModel = ViewModelProvider(
      owner,
      RuntimeHostViewModel.factory(context),
    )[RuntimeHostViewModel::class.java]
    return ViewModelHarness(owner, viewModel)
  }
}

private class ViewModelHarness(
  private val owner: TestViewModelOwner,
  val viewModel: RuntimeHostViewModel,
) : AutoCloseable {
  inline fun <reified T : RuntimeHostState> awaitState(
    crossinline predicate: (T) -> Boolean = { true },
  ): T {
    repeat(300) {
      shadowOf(android.os.Looper.getMainLooper()).idle()
      val state = viewModel.state.value
      if (state is T && predicate(state)) return state
      Thread.sleep(5)
    }
    error("Timed out waiting for ${T::class.java.simpleName}: ${viewModel.state.value}")
  }

  fun awaitPhase(phase: IdentityPromptPhase) =
    awaitState<RuntimeHostState.AuthenticationRequired> { it.phase == phase }

  override fun close() {
    owner.viewModelStore.clear()
  }
}

private class TestViewModelOwner : ViewModelStoreOwner {
  override val viewModelStore = ViewModelStore()
}

private class FakeIdentityClient(initialStatus: MobileIdentityStatus) : MobileIdentityClient {
  private var current = initialStatus
  var nextStatus: MobileIdentityStatus = initialStatus
  val accountSelectionPrompts = mutableListOf<Boolean>()

  override fun status(): MobileIdentityStatus = current

  override fun beginAuthorization(forceAccountSelection: Boolean): MobileIdentityAuthorizationStart {
    accountSelectionPrompts += forceAccountSelection
    return MobileIdentityAuthorizationStart(
      authorizationUrl = "https://identity.example.test/authorize?state=redacted",
      expiresAt = "2026-07-19T08:10:00Z",
    )
  }

  override fun completeAuthorization(callbackUrl: String): MobileIdentityStatus {
    if (callbackUrl.contains("forged")) {
      throw MobileIdentityBridgeException("identity_request_invalid", "Identity callback rejected")
    }
    current = nextStatus
    return current
  }

  override fun refresh(): MobileIdentityStatus = current

  override fun gatewayCredential(): RuntimeGatewayCredential = RuntimeGatewayCredential(
    bearerToken = "short-lived-assertion",
    securityContext = checkNotNull(current.securityContext),
  )

  override fun logout(): MobileIdentityLogout {
    current = signedOutStatus()
    return MobileIdentityLogout(null, "not_supported", current)
  }

  override fun close() = Unit
}

private class IdentityScopedNativeRuntime : NativeRuntimeApi {
  val events = mutableListOf<String>()
  private var nextHandle = 0L
  private val accountByHandle = linkedMapOf<Long, Pair<String, String>>()

  override fun initialize(requestJson: String): String {
    val context = JSONObject(requestJson).getJSONObject("security_context")
    val subject = context.getJSONObject("principal").getString("subject")
    val securityContext = context.toRuntimeSecurityContext()
    val handle = ++nextHandle
    accountByHandle[handle] = subject to securityContext.scopedAccountId()
    events += "initialize:$subject"
    return ok(JSONObject().put("handle", handle))
  }

  override fun invoke(handle: Long, requestJson: String): String {
    val operation = JSONObject(requestJson).getString("operation")
    val account = checkNotNull(accountByHandle[handle])
    return when (operation) {
      "diagnostics" -> ok(diagnostics(account.second))
      "refresh_security_context" -> ok(JSONObject.NULL)
      else -> error("unexpected operation: $operation")
    }
  }

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
    error("not used")

  override fun close(handle: Long): String {
    events += "close:$handle"
    accountByHandle.remove(handle)
    return ok(JSONObject.NULL)
  }

  private fun diagnostics(accountId: String): JSONObject = JSONObject()
    .put("app_id", "com.example.mobile")
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

private object HostSkillAssets : SkillAssetSource {
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

private fun JSONObject.toRuntimeSecurityContext(): RuntimeSecurityContext {
  val principal = getJSONObject("principal")
  return RuntimeSecurityContext(
    schemaVersion = getInt("schemaVersion"),
    providerId = getString("providerId"),
    appId = getString("appId"),
    tenantId = getString("tenantId"),
    audience = getString("audience"),
    principal = RuntimePrincipalIdentity(
      issuer = principal.getString("issuer"),
      subject = principal.getString("subject"),
    ),
    grantedScopes = emptyList(),
    authenticatedAt = getString("authenticatedAt"),
    expiresAt = getString("expiresAt"),
  )
}

private fun signedOutStatus() = MobileIdentityStatus(
  state = MobileIdentitySessionState.SignedOut,
  appId = "com.example.mobile",
  appDisplayName = "Managed Mobile",
  providerId = "agentweave.identity.oidc",
  accountId = null,
  securityContext = null,
)

private fun signedInStatus(subject: String): MobileIdentityStatus {
  val context = identityContext(subject, "2026-07-21T09:00:00Z")
  return MobileIdentityStatus(
    state = MobileIdentitySessionState.SignedIn,
    appId = context.appId,
    appDisplayName = "Managed Mobile",
    providerId = context.providerId,
    accountId = context.scopedAccountId(),
    securityContext = context,
  )
}

private fun expiredStatus(subject: String): MobileIdentityStatus {
  val context = identityContext(subject, "2026-07-19T08:30:00Z")
  return MobileIdentityStatus(
    state = MobileIdentitySessionState.Expired,
    appId = context.appId,
    appDisplayName = "Managed Mobile",
    providerId = context.providerId,
    accountId = context.scopedAccountId(),
    securityContext = context,
  )
}

private fun identityContext(subject: String, expiresAt: String) = RuntimeSecurityContext(
  providerId = "agentweave.identity.oidc",
  appId = "com.example.mobile",
  tenantId = "local",
  audience = "https://gateway.example.test",
  principal = RuntimePrincipalIdentity(
    issuer = "https://identity.example.test",
    subject = subject,
  ),
  grantedScopes = listOf("openid", "profile"),
  authenticatedAt = "2026-07-19T08:00:00Z",
  expiresAt = expiresAt,
)

package com.agentweave.mobile.runtime

import android.content.Context
import com.agentweave.mobile.secrets.IdentityMasterKeyStore
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class MobileIdentityBridgeTest {
  @Test
  fun localAppDoesNotOpenIdentityKeyVault() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = FakeNativeIdentity(localStatus())
    val forbidden = object : IdentityMasterKeyStore {
      override fun <T> withMasterKey(block: (ByteArray) -> T): T =
        error("local App must not open the identity key vault")
    }

    val bridge = MobileIdentityBridge.load(
      context = context,
      native = native,
      masterKeyStore = forbidden,
      appAssets = MissingAppAssets,
    )

    assertEquals(MobileIdentitySessionState.NotRequired, bridge.status().state)
    assertEquals(0, native.initializationKeySize)
    bridge.close()
  }

  @Test
  fun requiredIdentityParsesContextAndKeepsGatewayCredentialTransient() {
    val context = RuntimeEnvironment.getApplication() as Context
    val status = signedInStatus("account-a")
    val native = FakeNativeIdentity(status)
    val bridge = MobileIdentityBridge.load(
      context = context,
      native = native,
      masterKeyStore = FixedMasterKeyStore,
      appAssets = RequiredAppAssets,
    )

    val loaded = bridge.status()
    assertEquals(MobileIdentitySessionState.SignedIn, loaded.state)
    assertEquals("account-a", loaded.securityContext?.principal?.subject)
    assertEquals(32, native.initializationKeySize)

    val credential = bridge.gatewayCredential()
    assertEquals("short-lived-assertion", credential.bearerToken)
    assertEquals(loaded.securityContext, credential.securityContext)
    assertTrue(native.requests.none { it.contains("short-lived-assertion") })

    bridge.completeAuthorization("com.example.mobile:/oidc/callback?code=redacted&state=redacted")
    assertTrue(native.requests.last().contains("complete_authorization"))
    bridge.close()
  }

  @Test
  fun unexpectedNativeFieldsAreRejected() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = FakeNativeIdentity(
      JSONObject(localStatus()).put("unexpected", true).toString(),
    )
    val bridge = MobileIdentityBridge.load(
      context = context,
      native = native,
      masterKeyStore = FixedMasterKeyStore,
      appAssets = MissingAppAssets,
    )

    assertThrows(MobileIdentityBridgeException::class.java) { bridge.status() }
    bridge.close()
  }
}

private class FakeNativeIdentity(
  private val status: String,
) : NativeIdentityApi {
  var initializationKeySize = -1
  val requests = mutableListOf<String>()

  override fun initialize(requestJson: String, masterKey: ByteArray): String {
    initializationKeySize = masterKey.size
    return ok(JSONObject().put("handle", 91L))
  }

  override fun invoke(handle: Long, requestJson: String): String {
    requests += requestJson
    return when (JSONObject(requestJson).getString("operation")) {
      "status", "complete_authorization", "refresh" -> ok(JSONObject(status))
      "begin_authorization" -> ok(
        JSONObject()
          .put("authorizationUrl", "https://identity.example.test/authorize?state=redacted")
          .put("expiresAt", "2026-07-19T08:10:00Z"),
      )
      "gateway_credential" -> ok(
        JSONObject()
          .put("bearerToken", "short-lived-assertion")
          .put("securityContext", JSONObject(status).getJSONObject("securityContext")),
      )
      "logout" -> ok(
        JSONObject()
          .put("endSessionUrl", JSONObject.NULL)
          .put("remoteRevocation", "not_supported")
          .put("status", JSONObject(localStatus()).put("state", "signed_out")),
      )
      else -> error("unexpected identity operation")
    }
  }

  override fun close(handle: Long): String = ok(JSONObject.NULL)

  private fun ok(data: Any): String = JSONObject().put("ok", true).put("data", data).toString()
}

private object FixedMasterKeyStore : IdentityMasterKeyStore {
  override fun <T> withMasterKey(block: (ByteArray) -> T): T = block(ByteArray(32) { 7 })
}

private object MissingAppAssets : AgentAppAssetSource {
  override fun isAvailable(): Boolean = false
  override fun contentHash(): String = error("not used")
  override fun files(): List<String> = error("not used")
  override fun open(relativePath: String): InputStream = error("not used")
}

private object RequiredAppAssets : AgentAppAssetSource {
  private val manifest = """{"identity":{"mode":"required"}}"""
    .toByteArray(StandardCharsets.UTF_8)

  override fun isAvailable(): Boolean = true

  override fun contentHash(): String {
    val digest = MessageDigest.getInstance("SHA-256")
    digest.update("agent-app.json".toByteArray(StandardCharsets.UTF_8))
    digest.update(0)
    digest.update(manifest.size.toString().toByteArray(StandardCharsets.US_ASCII))
    digest.update(0)
    digest.update(manifest)
    return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
  }

  override fun files(): List<String> = listOf("agent-app.json")

  override fun open(relativePath: String): InputStream = ByteArrayInputStream(manifest)
}

private fun localStatus(): String = JSONObject()
  .put("state", "not_required")
  .put("appId", "dev.agentweave.default")
  .put("appDisplayName", "AgentWeave")
  .put("providerId", JSONObject.NULL)
  .put("accountId", JSONObject.NULL)
  .put("securityContext", JSONObject.NULL)
  .toString()

private fun signedInStatus(subject: String): String {
  val context = JSONObject()
    .put("schemaVersion", 1)
    .put("providerId", "agentweave.identity.oidc")
    .put("appId", "com.example.mobile")
    .put("tenantId", "local")
    .put("audience", "https://gateway.example.test")
    .put(
      "principal",
      JSONObject()
        .put("issuer", "https://identity.example.test")
        .put("subject", subject),
    )
    .put("grantedScopes", org.json.JSONArray(listOf("openid", "profile")))
    .put("authenticatedAt", "2026-07-19T08:00:00Z")
    .put("expiresAt", "2026-07-19T09:00:00Z")
  return JSONObject()
    .put("state", "signed_in")
    .put("appId", "com.example.mobile")
    .put("appDisplayName", "Managed Mobile")
    .put("providerId", "agentweave.identity.oidc")
    .put("accountId", "usr_${"a".repeat(64)}")
    .put("securityContext", context)
    .toString()
}

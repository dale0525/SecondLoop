package com.agentweave.mobile.runtime

import android.content.Context
import com.agentweave.mobile.secrets.AndroidKeystoreIdentityMasterKeyStore
import com.agentweave.mobile.secrets.IdentityMasterKeyStore
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

class MobileIdentityBridge private constructor(
  private val handle: Long,
  private val native: NativeIdentityApi,
) : MobileIdentityClient {
  private val closed = AtomicBoolean(false)

  override fun status(): MobileIdentityStatus =
    responseData(native.invoke(handle, JSONObject().put("operation", "status").toString()))
      .toIdentityStatus()

  override fun beginAuthorization(forceAccountSelection: Boolean): MobileIdentityAuthorizationStart {
    val data = responseData(
      native.invoke(
        handle,
        JSONObject()
          .put("operation", "begin_authorization")
          .put("force_account_selection", forceAccountSelection)
          .toString(),
      ),
    )
    data.requireExactKeys("authorizationUrl", "expiresAt")
    return MobileIdentityAuthorizationStart(
      authorizationUrl = data.getString("authorizationUrl"),
      expiresAt = data.getString("expiresAt"),
    )
  }

  override fun completeAuthorization(callbackUrl: String): MobileIdentityStatus =
    responseData(
      native.invoke(
        handle,
        JSONObject()
          .put("operation", "complete_authorization")
          .put("callback_url", callbackUrl)
          .toString(),
      ),
    ).toIdentityStatus()

  override fun refresh(): MobileIdentityStatus =
    responseData(native.invoke(handle, JSONObject().put("operation", "refresh").toString()))
      .toIdentityStatus()

  override fun gatewayCredential(): RuntimeGatewayCredential {
    val data = responseData(
      native.invoke(handle, JSONObject().put("operation", "gateway_credential").toString()),
    )
    data.requireExactKeys("bearerToken", "securityContext")
    val token = data.getString("bearerToken")
    if (token.isBlank()) {
      throw MobileIdentityBridgeException(
        "identity_response_invalid",
        "Identity response is invalid",
      )
    }
    return RuntimeGatewayCredential(
      bearerToken = token,
      securityContext = data.getJSONObject("securityContext").toSecurityContext(),
    )
  }

  override fun logout(): MobileIdentityLogout {
    val data = responseData(
      native.invoke(handle, JSONObject().put("operation", "logout").toString()),
    )
    data.requireExactKeys("endSessionUrl", "remoteRevocation", "status")
    return MobileIdentityLogout(
      endSessionUrl = data.nullableString("endSessionUrl"),
      remoteRevocation = data.getString("remoteRevocation"),
      status = data.getJSONObject("status").toIdentityStatus(),
    )
  }

  override fun close() {
    if (closed.compareAndSet(false, true)) responseEnvelope(native.close(handle))
  }

  companion object {
    fun load(
      context: Context,
      native: NativeIdentityApi = NativeIdentity,
      masterKeyStore: IdentityMasterKeyStore = AndroidKeystoreIdentityMasterKeyStore(context),
      tenantId: String = "local",
      appAssets: AgentAppAssetSource = AndroidAgentAppAssetSource(context.assets),
    ): MobileIdentityBridge {
      val installedApp = AgentAppAssetInstaller(context.filesDir, appAssets).install()
      val request = JSONObject()
        .put("app_data_dir", context.filesDir.absolutePath)
        .put("no_backup_dir", context.noBackupFilesDir.absolutePath)
        .put("app_package_dir", installedApp?.absolutePath ?: JSONObject.NULL)
        .put(
          "metadata_database_path",
          context.noBackupFilesDir.resolve("identity-vault/metadata.db").absolutePath,
        )
        .put(
          "secret_store_dir",
          context.noBackupFilesDir.resolve("identity-vault/secrets").absolutePath,
        )
        .put("tenant_id", tenantId)
      val response = if (installedApp.requiresRemoteIdentity()) {
        masterKeyStore.withMasterKey { masterKey ->
          native.initialize(request.toString(), masterKey)
        }
      } else {
        native.initialize(request.toString(), ByteArray(0))
      }
      val data = responseData(response)
      data.requireExactKeys("handle")
      return MobileIdentityBridge(data.getLong("handle"), native)
    }
  }
}

private fun java.io.File?.requiresRemoteIdentity(): Boolean {
  val manifest = this?.resolve("agent-app.json")?.takeIf(java.io.File::isFile) ?: return false
  return runCatching {
    JSONObject(manifest.readText(Charsets.UTF_8))
      .optJSONObject("identity")
      ?.optString("mode") == "required"
  }.getOrDefault(false)
}

private fun responseEnvelope(response: String): JSONObject {
  val envelope = try {
    JSONObject(response)
  } catch (_: Exception) {
    throw MobileIdentityBridgeException("identity_response_invalid", "Identity response is invalid")
  }
  if (!envelope.optBoolean("ok")) {
    val error = envelope.optJSONObject("error")
    throw MobileIdentityBridgeException(
      error?.optString("code")?.takeIf(String::isNotBlank) ?: "identity_operation_failed",
      error?.optString("message")?.takeIf(String::isNotBlank) ?: "Identity operation failed",
    )
  }
  envelope.requireExactKeys("ok", "data")
  return envelope
}

private fun responseData(response: String): JSONObject = responseEnvelope(response).getJSONObject("data")

private fun JSONObject.toIdentityStatus(): MobileIdentityStatus {
  requireExactKeys(
    "state",
    "appId",
    "appDisplayName",
    "providerId",
    "accountId",
    "securityContext",
  )
  val state = MobileIdentitySessionState.fromWire(getString("state"))
  val context = optJSONObject("securityContext")?.toSecurityContext()
  val accountId = nullableString("accountId")
  val accountExpected = state == MobileIdentitySessionState.SignedIn ||
    state == MobileIdentitySessionState.Expired
  if (accountExpected != (context != null && accountId != null)) {
    throw MobileIdentityBridgeException("identity_response_invalid", "Identity response is invalid")
  }
  if (accountId != null && !OPAQUE_ACCOUNT_ID.matches(accountId)) {
    throw MobileIdentityBridgeException("identity_response_invalid", "Identity response is invalid")
  }
  return MobileIdentityStatus(
    state = state,
    appId = getString("appId"),
    appDisplayName = getString("appDisplayName"),
    providerId = nullableString("providerId"),
    accountId = accountId,
    securityContext = context,
  )
}

private fun JSONObject.toSecurityContext(): RuntimeSecurityContext {
  requireExactKeys(
    "schemaVersion",
    "providerId",
    "appId",
    "tenantId",
    "audience",
    "principal",
    "grantedScopes",
    "authenticatedAt",
    "expiresAt",
  )
  val principal = getJSONObject("principal").also {
    it.requireExactKeys("issuer", "subject")
  }
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
    grantedScopes = getJSONArray("grantedScopes").strings(),
    authenticatedAt = getString("authenticatedAt"),
    expiresAt = getString("expiresAt"),
  )
}

private fun JSONObject.requireExactKeys(vararg expected: String) {
  val actual = keys().asSequence().toSet()
  if (actual != expected.toSet()) {
    throw MobileIdentityBridgeException("identity_response_invalid", "Identity response is invalid")
  }
}

private fun JSONObject.nullableString(key: String): String? =
  if (isNull(key)) null else getString(key).takeIf(String::isNotBlank)

private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

private val OPAQUE_ACCOUNT_ID = Regex("^usr_[0-9a-f]{64}$")

package com.agentweave.mobile.runtime

import com.agentweave.mobile.secrets.ModelSecretStore
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

data class RuntimeAccountSession(
  val client: RuntimeClient,
  val diagnostics: RuntimeDiagnostics,
  val secretStore: ModelSecretStore,
)

/**
 * Owns the single active native runtime and enforces the account-switch order.
 * Identity plugins retain bearer material; this coordinator receives only the
 * verified non-secret context used to partition host state.
 */
class RuntimeAccountCoordinator(
  private val bridge: RuntimeBridge,
  private val secretStoreForAccount: (String?) -> ModelSecretStore,
  private val stopActiveWork: () -> Unit = {},
) : AutoCloseable {
  private var current: RuntimeAccountSession? = null

  @Synchronized
  fun start(
    securityContext: RuntimeSecurityContext? = null,
    gatewayCredentialProvider: RuntimeGatewayCredentialProvider? = null,
  ): RuntimeAccountSession {
    check(current == null) { "Runtime account session is already active" }
    return activate(securityContext, gatewayCredentialProvider)
  }

  @Synchronized
  fun switchAccount(
    securityContext: RuntimeSecurityContext?,
    gatewayCredentialProvider: RuntimeGatewayCredentialProvider? = null,
  ): RuntimeAccountSession {
    val previous = current ?: return activate(securityContext, gatewayCredentialProvider)
    current = null
    stopActiveWork()
    previous.client.close()
    return activate(securityContext, gatewayCredentialProvider)
  }

  @Synchronized
  fun session(): RuntimeAccountSession? = current

  @Synchronized
  override fun close() {
    val previous = current ?: return
    current = null
    stopActiveWork()
    previous.client.close()
  }

  private fun activate(
    securityContext: RuntimeSecurityContext?,
    gatewayCredentialProvider: RuntimeGatewayCredentialProvider?,
  ): RuntimeAccountSession {
    val expectedAccountId = securityContext?.scopedAccountId()
    val secretStore = secretStoreForAccount(expectedAccountId)
    val client = bridge.load(securityContext, gatewayCredentialProvider)
    try {
      val diagnostics = client.diagnostics()
      check(diagnostics.accountId == expectedAccountId) {
        "Native runtime account scope does not match the Android host scope"
      }
      return RuntimeAccountSession(client, diagnostics, secretStore).also { current = it }
    } catch (error: Exception) {
      runCatching { client.close() }.exceptionOrNull()?.let(error::addSuppressed)
      throw error
    }
  }
}

internal fun RuntimeSecurityContext.scopedAccountId(): String {
  val digest = MessageDigest.getInstance("SHA-256")
  digest.update("agentweave.identity.account.v1\u0000".toByteArray(StandardCharsets.UTF_8))
  listOf(appId, tenantId, providerId, principal.issuer, principal.subject).forEach { value ->
    val bytes = value.toByteArray(StandardCharsets.UTF_8)
    digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(bytes.size.toLong()).array())
    digest.update(bytes)
  }
  return "usr_" + digest.digest().joinToString(separator = "") { byte ->
    "%02x".format(byte.toInt() and 0xff)
  }
}

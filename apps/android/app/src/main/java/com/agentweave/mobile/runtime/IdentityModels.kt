package com.agentweave.mobile.runtime

enum class MobileIdentitySessionState(val wireValue: String) {
  NotRequired("not_required"),
  SignedOut("signed_out"),
  SignedIn("signed_in"),
  Expired("expired"),
  Unavailable("unavailable");

  companion object {
    fun fromWire(value: String): MobileIdentitySessionState =
      entries.firstOrNull { it.wireValue == value }
        ?: throw MobileIdentityBridgeException("identity_response_invalid", "Identity response is invalid")
  }
}

data class MobileIdentityStatus(
  val state: MobileIdentitySessionState,
  val appId: String,
  val appDisplayName: String,
  val providerId: String?,
  val accountId: String?,
  val securityContext: RuntimeSecurityContext?,
)

data class MobileIdentityAuthorizationStart(
  val authorizationUrl: String,
  val expiresAt: String,
)

data class MobileIdentityLogout(
  val endSessionUrl: String?,
  val remoteRevocation: String,
  val status: MobileIdentityStatus,
)

class MobileIdentityBridgeException(
  val code: String,
  message: String,
) : IllegalStateException(message) {
  val authenticationRequired: Boolean
    get() = code == "identity_authentication_required" || code == "identity_access_denied"
}

interface MobileIdentityClient : AutoCloseable {
  fun status(): MobileIdentityStatus

  fun beginAuthorization(forceAccountSelection: Boolean = false): MobileIdentityAuthorizationStart

  fun completeAuthorization(callbackUrl: String): MobileIdentityStatus

  fun refresh(): MobileIdentityStatus

  fun gatewayCredential(): RuntimeGatewayCredential

  fun logout(): MobileIdentityLogout
}

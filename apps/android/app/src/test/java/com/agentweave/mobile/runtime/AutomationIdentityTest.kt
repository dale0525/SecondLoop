package com.agentweave.mobile.runtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class AutomationIdentityTest {
  @Test
  fun signedOutBackgroundWorkSkipsWithoutOpeningAnotherAccount() {
    val result = resolveBackgroundIdentity(status(MobileIdentitySessionState.SignedOut)) {
      error("signed-out sessions must not refresh in background")
    }

    assertSame(BackgroundIdentityResolution.Skip, result)
  }

  @Test
  fun expiredBackgroundSessionMustRefreshBeforeRuntimeInitialization() {
    val refreshed = status(
      MobileIdentitySessionState.SignedIn,
      securityContext = context("account-a"),
    )
    val result = resolveBackgroundIdentity(
      status(
        MobileIdentitySessionState.Expired,
        securityContext = context("account-a"),
      ),
    ) { refreshed }

    val authenticated = result as BackgroundIdentityResolution.Authenticated
    assertEquals("account-a", authenticated.securityContext.principal.subject)
  }

  @Test
  fun unavailableBackgroundIdentityRetriesFailClosed() {
    assertSame(
      BackgroundIdentityResolution.Retry,
      resolveBackgroundIdentity(status(MobileIdentitySessionState.Unavailable)) {
        error("not used")
      },
    )
  }

  private fun status(
    state: MobileIdentitySessionState,
    securityContext: RuntimeSecurityContext? = null,
  ) = MobileIdentityStatus(
    state = state,
    appId = "com.example.mobile",
    appDisplayName = "Managed Mobile",
    providerId = "agentweave.identity.oidc",
    accountId = securityContext?.scopedAccountId(),
    securityContext = securityContext,
  )

  private fun context(subject: String) = RuntimeSecurityContext(
    providerId = "agentweave.identity.oidc",
    appId = "com.example.mobile",
    tenantId = "local",
    audience = "https://gateway.example.test",
    principal = RuntimePrincipalIdentity(
      issuer = "https://identity.example.test",
      subject = subject,
    ),
    grantedScopes = listOf("openid"),
    authenticatedAt = "2026-07-19T08:00:00Z",
    expiresAt = "2026-07-21T08:00:00Z",
  )
}

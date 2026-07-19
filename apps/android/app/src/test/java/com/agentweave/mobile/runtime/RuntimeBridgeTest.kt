package com.agentweave.mobile.runtime

import android.content.Context
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RuntimeBridgeTest {
  @Test
  fun loadInitializesNativeRuntimeWithAppPrivatePathsAndCapabilities() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = RecordingNativeRuntime()

    val client = RuntimeBridge(
      context,
      native,
      BridgeSkillAssets(),
      publicationFileSystem = JvmSkillPublicationFileSystem(),
    ).load()
    val request = JSONObject(native.initializeRequest)

    assertEquals(41L, client.handle)
    assertEquals(context.filesDir.absolutePath, request.getString("app_data_dir"))
    assertEquals(context.cacheDir.absolutePath, request.getString("cache_dir"))
    assertTrue(request.getString("database_path").startsWith(context.filesDir.absolutePath))
    assertTrue(request.getString("builtin_skills_dir").startsWith(context.filesDir.absolutePath))
    assertTrue(request.getString("managed_skills_dir").startsWith(context.filesDir.absolutePath))
    assertTrue(request.getString("staging_skills_dir").startsWith(context.cacheDir.absolutePath))
    assertTrue(request.getString("quarantine_skills_dir").startsWith(context.filesDir.absolutePath))
    assertEquals("disabled", request.getJSONObject("skill_policy").getString("mode"))
    assertEquals("anonymous", request.getJSONObject("actor_context").getString("actor_id"))
    assertEquals("android", request.getString("platform"))
    assertEquals(androidMvpCapabilities().size, request.getJSONArray("capabilities").length())
    assertFalse(native.initializeRequest.contains("api_key", ignoreCase = true))
  }

  @Test
  fun loadSerializesOnlyNonSecretVerifiedIdentityFacts() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = RecordingNativeRuntime()
    val securityContext = testSecurityContext("account-a")

    val client = RuntimeBridge(
      context = context,
      native = native,
      skillAssets = BridgeSkillAssets(),
      publicationFileSystem = JvmSkillPublicationFileSystem(),
      configuredSecurityContext = securityContext,
    ).load()
    val identity = JSONObject(native.initializeRequest).getJSONObject("security_context")

    assertEquals(securityContext, client.securityContext)
    assertEquals(1, identity.getInt("schemaVersion"))
    assertEquals("agentweave.identity.oidc", identity.getString("providerId"))
    assertEquals("account-a", identity.getJSONObject("principal").getString("subject"))
    assertEquals(listOf("openid", "profile"), identity.getJSONArray("grantedScopes").let { scopes ->
      List(scopes.length()) { scopes.getString(it) }
    })
    assertFalse(native.initializeRequest.contains("access_token", ignoreCase = true))
    assertFalse(native.initializeRequest.contains("refresh_token", ignoreCase = true))
    assertFalse(native.initializeRequest.contains("bearer", ignoreCase = true))
  }

  @Test
  fun configuredPolicyAndActorAreStoredOnlyInInitialization() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = RecordingNativeRuntime()
    val policy = RuntimeSkillPolicy(
      mode = "owner_only",
      agentAuthoring = true,
      allowedKinds = listOf("instruction_only"),
      protectedPackages = listOf("com.example.protected"),
      allowedOverrides = listOf("com.example.override"),
    )
    val actor = RuntimeActorContext(
      actorId = "android-owner",
      role = "owner",
      tenantId = "tenant-1",
      deviceId = "device-1",
      grants = listOf("inspect", "create_draft"),
    )

    RuntimeBridge(
      context,
      native,
      BridgeSkillAssets(),
      policy,
      actor,
      JvmSkillPublicationFileSystem(),
    ).load()
    val request = JSONObject(native.initializeRequest)

    assertEquals("owner_only", request.getJSONObject("skill_policy").getString("mode"))
    assertEquals("com.example.protected", request.getJSONObject("skill_policy").getJSONArray("protected_packages").getString(0))
    assertEquals("com.example.override", request.getJSONObject("skill_policy").getJSONArray("allowed_overrides").getString(0))
    assertEquals("android-owner", request.getJSONObject("actor_context").getString("actor_id"))
    assertFalse(native.initializeRequest.contains("actor_override"))
  }

  @Test
  fun diagnosticsExposeIdentityAndModelConfigurationPolicy() {
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String =
        """{"ok":true,"data":{"app_id":"com.example.managed","app_version":"0.1.0","app_display_name":"Managed","platform":"android","capabilities":[],"database_ready":true,"skills_ready":true,"model_configured":true,"model_configuration_policy":"app_managed","identity_mode":"required","account_id":"usr_${"a".repeat(64)}","skill_management_mode":"disabled","active_snapshot_generation":1,"quarantined_count":0,"last_reload_status":"ready"}}"""

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }

    val diagnostics = RuntimeClient(7L, native).diagnostics()

    assertEquals("app_managed", diagnostics.modelConfigurationPolicy)
    assertEquals("required", diagnostics.identityMode)
    assertEquals("usr_${"a".repeat(64)}", diagnostics.accountId)
  }

  @Test
  fun bridgeCreatesDistinctRequesterAndApproverClients() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = MultiHandleNativeRuntime()
    val policy = RuntimeSkillPolicy(
      mode = "owner_only",
      agentAuthoring = true,
      allowedKinds = listOf("instruction_only"),
    )
    val requester = RuntimeActorContext(
      actorId = "android-requester",
      role = "owner",
      grants = listOf("inspect", "activate"),
    )
    val approver = RuntimeActorContext(
      actorId = "android-approver",
      role = "owner",
      grants = listOf("inspect", "activate"),
    )

    val client = RuntimeBridge(
      context = context,
      native = native,
      skillAssets = BridgeSkillAssets(),
      configuredSkillPolicy = policy,
      configuredActorContext = requester,
      configuredApproverContext = approver,
      publicationFileSystem = JvmSkillPublicationFileSystem(),
    ).load()
    val resolution = client.resolveSkillApproval("approval-1", approve = true)

    assertEquals(listOf("android-requester", "android-approver"), native.initializeActors)
    assertEquals(listOf(102L, 102L, 101L), native.invokeHandles)
    assertEquals("android-approver", client.approverActorId)
    assertTrue(client.approvalAvailable)
    assertEquals("owner", client.approverAccess?.actorContext?.role)
    assertEquals(listOf("inspect", "activate"), client.approverAccess?.actorContext?.grants)
    assertEquals(policy, client.approverAccess?.skillPolicy)
    assertNull(resolution.synchronizationWarning)
  }

  @Test
  fun missingDistinctApproverDisablesApprovalResolution() {
    val client = RuntimeClient(
      handle = 9L,
      native = OwnerNativeRuntime(),
      actorContext = RuntimeActorContext(actorId = "same-owner", role = "owner"),
      approverClient = RuntimeApprovalClient(
        handle = 10L,
        native = OwnerNativeRuntime(),
        actorContext = RuntimeActorContext(
          actorId = "same-owner",
          role = "owner",
          grants = listOf("activate"),
        ),
        skillPolicy = ownerApprovalPolicy(),
      ),
    )

    assertFalse(client.approvalAvailable)
    assertEquals("A distinct approving actor is unavailable", client.approvalUnavailableReason)
    assertThrows(RuntimeBridgeException::class.java) {
      client.resolveSkillApproval("approval-1", approve = true)
    }
  }

  @Test
  fun approverAuthorityRequiresDistinctOperationGrantAndOverride() {
    val native = OwnerNativeRuntime()
    val policy = RuntimeSkillPolicy(
      mode = "owner_only",
      allowedKinds = listOf("instruction_only"),
      allowedOverrides = listOf("com.example.owner"),
    )
    fun client(approver: RuntimeActorContext) = RuntimeClient(
      handle = 9L,
      native = native,
      actorContext = RuntimeActorContext(actorId = "requester", role = "owner"),
      skillPolicy = policy,
      approverClient = RuntimeApprovalClient(10L, native, approver, policy),
    )

    val self = client(
      RuntimeActorContext(actorId = "requester", role = "owner", grants = listOf("activate")),
    ).approvalAuthority(
      RuntimeSkillApprovalOperation.Activation,
      "com.example.owner",
      "instruction_only",
      overrideRequired = false,
    )
    val insufficient = client(
      RuntimeActorContext(actorId = "approver", role = "owner", grants = listOf("inspect")),
    ).approvalAuthority(
      RuntimeSkillApprovalOperation.Activation,
      "com.example.owner",
      "instruction_only",
      overrideRequired = false,
    )
    val missingOverride = client(
      RuntimeActorContext(actorId = "approver", role = "owner", grants = listOf("activate")),
    ).approvalAuthority(
      RuntimeSkillApprovalOperation.Activation,
      "com.example.owner",
      "instruction_only",
      overrideRequired = true,
    )
    val allowed = client(
      RuntimeActorContext(
        actorId = "approver",
        role = "owner",
        grants = listOf("activate", "override_builtin"),
      ),
    ).approvalAuthority(
      RuntimeSkillApprovalOperation.Activation,
      "com.example.owner",
      "instruction_only",
      overrideRequired = true,
    )

    assertFalse(self.available)
    assertTrue(self.reason.contains("distinct", ignoreCase = true))
    assertFalse(insufficient.available)
    assertTrue(insufficient.reason.contains("activate"))
    assertFalse(missingOverride.available)
    assertTrue(missingOverride.reason.contains("override"))
    assertTrue(allowed.available)
    assertEquals("approver", client(RuntimeActorContext(actorId = "approver")).approverAccess?.actorContext?.actorId)
  }

  @Test
  fun approverAuthorityUsesRollbackAndRemovalGrants() {
    val native = OwnerNativeRuntime()
    val policy = RuntimeSkillPolicy(mode = "owner_only", allowedKinds = listOf("instruction_only"))
    val client = RuntimeClient(
      handle = 9L,
      native = native,
      actorContext = RuntimeActorContext(actorId = "requester", role = "owner"),
      skillPolicy = policy,
      approverClient = RuntimeApprovalClient(
        10L,
        native,
        RuntimeActorContext(actorId = "approver", role = "owner", grants = listOf("rollback")),
        policy,
      ),
    )

    assertTrue(
      client.approvalAuthority(
        RuntimeSkillApprovalOperation.Rollback,
        "com.example.owner",
        "instruction_only",
        overrideRequired = false,
      ).available,
    )
    assertFalse(
      client.approvalAuthority(
        RuntimeSkillApprovalOperation.Removal,
        "com.example.owner",
        "instruction_only",
        overrideRequired = false,
      ).available,
    )
  }

  @Test
  fun createDraftCarriesInitialFilesWithoutEditOperation() {
    val native = OwnerNativeRuntime()
    val client = RuntimeClient(9L, native)
    val request = RuntimeSkillDraftRequest(
      packageId = "com.example.created",
      displayName = "Created",
      description = "Description",
      kind = "instruction_only",
      requiredTools = emptyList(),
      initialFiles = listOf(RuntimeSkillDraftFile("SKILL.md", "Initial instructions")),
    )

    client.createSkillDraft(request)

    assertEquals(listOf("create_skill_draft"), native.requests.map { it.getString("operation") })
    assertEquals("Initial instructions", native.requests.single().getJSONArray("files").getJSONObject(0).getString("content"))
  }

  @Test
  fun rollbackOutcomePreservesAuthoritativeApprovalFacts() {
    val native = OwnerNativeRuntime(rollbackApproval = true)
    val outcome = RuntimeClient(9L, native).rollbackManagedSkill("com.example.owner", "revision-old")

    val approval = (outcome as RuntimeSkillRollbackOutcome.ApprovalRequired).approval
    assertEquals("mobile-requester", approval.requestedBy)
    assertEquals("{}", approval.permissionDiffJson)
  }

  @Test
  fun approvalPublicationSurvivesRequesterSynchronizationFailure() {
    val native = SynchronizationFailureNativeRuntime()
    val client = RuntimeClient(
      handle = 9L,
      native = native,
      actorContext = RuntimeActorContext(actorId = "requester", role = "owner"),
      approverClient = testApprovalClient(native),
    )

    val resolution = client.resolveSkillApproval("approval-1", approve = true)
    val synchronized = client.synchronizeSkills()
    val refreshed = client.listSkills()

    assertEquals("approved", resolution.mutation.status)
    assertEquals(8L, resolution.mutation.activeGeneration)
    assertTrue(resolution.synchronizationWarning?.contains("synchronization failed") == true)
    assertEquals(8L, synchronized.activeSnapshotGeneration)
    assertTrue(refreshed.isEmpty())
    assertEquals(1, native.operations.count { it == "resolve_skill_approval" })
    assertEquals(
      listOf(
        "synchronize_skills",
        "resolve_skill_approval",
        "synchronize_skills",
        "synchronize_skills",
        "list_skills",
      ),
      native.operations,
    )
  }

  @Test
  fun failedSynchronizationRetryDoesNotResolveApprovalAgain() {
    val native = SynchronizationFailureNativeRuntime(recoverySucceeds = false)
    val client = RuntimeClient(
      handle = 9L,
      native = native,
      actorContext = RuntimeActorContext(actorId = "requester", role = "owner"),
      approverClient = testApprovalClient(native),
    )

    val resolution = client.resolveSkillApproval("approval-1", approve = true)
    assertThrows(RuntimeBridgeException::class.java) { client.synchronizeSkills() }

    assertTrue(resolution.synchronizationWarning != null)
    assertEquals(1, native.operations.count { it == "resolve_skill_approval" })
    assertEquals(3, native.operations.count { it == "synchronize_skills" })
  }

  @Test
  fun loadModelConfigPreservesNullSecretReference() {
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String =
        """{"ok":true,"data":{"provider_id":"local","provider_name":"Local","endpoint_type":"responses","base_url":"http://localhost:11434/v1","model_name":"qwen","secret_id":null,"headers":{}}}"""

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }

    val config = RuntimeClient(9L, native).loadModelConfig()

    assertNull(config?.secretId)
  }

  @Test
  fun listSkillsPreservesRuntimeAvailabilityReasons() {
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String =
        """{"ok":true,"data":[{"package_id":"com.example.web-browser","display_name":"Web browser","version":"1.2.3","source_layer":"builtin","status":"capability_missing","available":false,"reason":"Missing required capability: browser.headless","active_revision_id":null,"manageable":false}]}"""

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }

    val skills = RuntimeClient(9L, native).listSkills()

    assertEquals(1, skills.size)
    assertEquals("com.example.web-browser", skills.single().packageId)
    assertEquals("builtin", skills.single().sourceLayer)
    assertEquals("capability_missing", skills.single().status)
    assertFalse(skills.single().available)
    assertEquals("Missing required capability: browser.headless", skills.single().reason)
  }

  @Test
  fun listSkillsPreservesLayeredWinnerCollisionAndAuthoritativeActions() {
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String =
        """{"ok":true,"data":[{"package_id":"com.example.collision","display_name":"Built-in winner","version":"1.0.0","source_layer":"builtin","status":"active","available":true,"reason":"active","active_revision_id":"builtin:abc","manageable":false,"built_in_collision":true,"effective":{"package_id":"com.example.collision","display_name":"Built-in winner","version":"1.0.0","source_layer":"builtin","status":"active","reason":"active","active_revision_id":"builtin:abc","manageable":false,"available":true,"content_hash":"abc"},"managed":{"package_id":"com.example.collision","display_name":"Managed draft","version":"2.0.0","source_layer":"managed","status":"disabled","reason":"disabled","active_revision_id":"revision-2","manageable":true,"available":false,"content_hash":"def"},"actions":{"can_edit_draft":false,"can_validate_draft":false,"can_request_activation":false,"can_disable":false,"can_request_removal":true,"can_rollback":false}}]}"""

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }

    val skill = RuntimeClient(9L, native).listSkills().single()

    assertEquals("builtin", skill.sourceLayer)
    assertEquals("builtin:abc", skill.activeRevisionId)
    assertEquals("disabled", skill.managed?.status)
    assertTrue(skill.builtInCollision)
    assertTrue(skill.actions.canRequestRemoval)
    assertFalse(skill.actions.canRequestActivation)
  }

  @Test
  fun listSkillsKeepsUnavailableEffectiveSeparateFromActiveInstallationActions() {
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String =
        """{"ok":true,"data":[{"package_id":"com.example.circuit","display_name":"Circuit skill","version":"2.0.0","source_layer":"managed","status":"circuit_open","available":false,"reason":"managed revision circuit open","active_revision_id":"revision-2","manageable":true,"built_in_collision":false,"effective":{"package_id":"com.example.circuit","display_name":"Circuit skill","version":"2.0.0","source_layer":"managed","status":"circuit_open","reason":"managed revision circuit open","active_revision_id":"revision-2","manageable":true,"available":false,"content_hash":"abc"},"managed":{"package_id":"com.example.circuit","display_name":"Circuit skill","version":"2.0.0","source_layer":"managed","status":"active","reason":"active","active_revision_id":"revision-2","manageable":true,"available":true,"content_hash":"abc"},"actions":{"can_edit_draft":false,"can_validate_draft":false,"can_request_activation":false,"can_disable":true,"can_request_removal":true,"can_rollback":true}}]}"""

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }

    val skill = RuntimeClient(9L, native).listSkills().single()

    assertEquals("circuit_open", skill.status)
    assertEquals("managed revision circuit open", skill.reason)
    assertFalse(skill.available)
    assertEquals("circuit_open", skill.effective?.status)
    assertEquals("active", skill.managed?.status)
    assertTrue(skill.actions.canDisable)
    assertTrue(skill.actions.canRollback)
  }

  @Test
  fun ownerOperationsUseStoredActorAndMapRuntimeDtos() {
    val native = OwnerNativeRuntime()
    val client = RuntimeClient(
      handle = 9L,
      native = native,
      skillGrants = setOf("inspect", "activate"),
      actorContext = RuntimeActorContext(actorId = "owner", role = "owner"),
      approverClient = testApprovalClient(native),
    )

    val managed = client.listManagedSkills().single()
    val detail = client.getSkillDetail("com.example.owner")
    val draft = client.createSkillDraft(
      RuntimeSkillDraftRequest(
        packageId = "com.example.new-skill",
        displayName = "New skill",
        description = "Owner authored instructions",
        kind = "instruction_only",
        requiredTools = listOf("host/search"),
      ),
    )
    client.updateSkillDraft(
      revisionId = draft.revisionId,
      files = listOf(RuntimeSkillDraftFile("instructions.md", "Updated instructions")),
    )
    val validation = client.validateSkillDraft(draft.revisionId)
    val approval = client.requestSkillActivation(draft.revisionId)
    val reload = client.resolveSkillApproval(approval.approvalId, approve = true)
    client.disableManagedSkill(managed.packageId)
    client.rollbackManagedSkill(managed.packageId, detail.revisions.last().revisionId)
    client.requestSkillRemoval(managed.packageId)

    assertEquals(setOf("inspect", "activate"), client.skillGrants)
    assertEquals("managed", managed.sourceLayer)
    assertTrue(managed.manageable)
    assertEquals("host_tools_only", detail.revisions.first().kind)
    assertEquals("Draft instructions", detail.editableDraft?.instructions)
    assertTrue(validation.ok)
    assertEquals(listOf("host/search"), validation.requiredTools)
    assertEquals("approval-1", approval.approvalId)
    assertEquals(8L, reload.mutation.activeGeneration)
    assertNull(reload.synchronizationWarning)
    assertTrue(native.requests.none { request ->
      request.has("actor") || request.has("actor_context") || request.has("principal")
    })
    assertEquals(
      listOf(
        "list_managed_skills",
        "get_skill_detail",
        "create_skill_draft",
        "update_skill_draft",
        "validate_skill_draft",
        "request_skill_activation",
        "synchronize_skills",
        "resolve_skill_approval",
        "synchronize_skills",
        "disable_managed_skill",
        "rollback_managed_skill",
        "request_skill_removal",
      ),
      native.requests.map { it.getString("operation") },
    )
  }

  @Test
  fun saveModelConfigAcceptsNullUnitPayload() {
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String =
        """{"ok":true,"data":null}"""

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }

    RuntimeClient(9L, native).saveModelConfig(
      RuntimeModelConfig(
        providerId = "local",
        providerName = "Local",
        endpointType = "responses",
        baseUrl = "http://localhost:11434/v1",
        modelName = "qwen",
        secretId = null,
      ),
    )
  }

  @Test
  fun automationOperationsPreserveLimitsClaimsAndDeliveryOutcomes() {
    val requests = mutableListOf<JSONObject>()
    val native = object : NativeRuntimeApi {
      override fun initialize(requestJson: String): String = error("not used")

      override fun invoke(handle: Long, requestJson: String): String {
        val request = JSONObject(requestJson)
        requests += request
        val data = when (request.getString("operation")) {
          "run_scheduler_tick" -> "2"
          "claim_notifications" ->
            """[{"notification_id":"notification-1","request":{"channel":"android","title":"Daily brief","body":"Two updates","data":{"route":"briefing"}},"status":"delivering","attempt_count":1}]"""
          "finish_notification" -> "true"
          else -> error("unexpected operation")
        }
        return """{"ok":true,"data":$data}"""
      }

      override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
        error("not used")

      override fun close(handle: Long): String = """{"ok":true,"data":null}"""
    }
    val client = RuntimeClient(9L, native)

    assertEquals(2, client.runSchedulerTick(limit = 7))
    val notification = client.claimNotifications(worker = "worker-1", limit = 3).single()
    assertEquals("notification-1", notification.notificationId)
    assertEquals("Daily brief", notification.title)
    assertEquals("{\"route\":\"briefing\"}", notification.dataJson)
    assertTrue(client.finishNotificationDelivered("notification-1", "worker-1", "android:42"))
    assertTrue(client.finishNotificationUncertain("notification-2", "worker-1", "delivery failed"))

    assertEquals(7, requests[0].getInt("limit"))
    assertEquals("worker-1", requests[1].getString("worker"))
    assertEquals(3, requests[1].getInt("limit"))
    assertEquals("delivered", requests[2].getJSONObject("outcome").getString("kind"))
    assertEquals("android:42", requests[2].getJSONObject("outcome").getString("delivery_id"))
    assertEquals("uncertain", requests[3].getJSONObject("outcome").getString("kind"))
    assertEquals("delivery failed", requests[3].getJSONObject("outcome").getString("message"))
  }

  @Test
  fun malformedSuccessfulInitializationClosesAllocatedHandle() {
    val context = RuntimeEnvironment.getApplication() as Context
    val native = RecordingNativeRuntime(
      initializeResponse = """{"ok":true,"data":{"handle":41,"unexpected":true}}""",
    )

    assertThrows(RuntimeBridgeException::class.java) {
      RuntimeBridge(
        context,
        native,
        BridgeSkillAssets(),
        publicationFileSystem = JvmSkillPublicationFileSystem(),
      ).load()
    }

    assertEquals(listOf(41L), native.closedHandles)
  }

  @Test
  fun runtimeClientCloseIsIdempotent() {
    val native = RecordingNativeRuntime()
    val client = RuntimeClient(41L, native)

    client.close()
    client.close()

    assertEquals(listOf(41L), native.closedHandles)
  }

  @Test
  fun runtimeClientCloseAttemptsBothHandlesAndAggregatesErrors() {
    val native = FailingCloseNativeRuntime()
    val client = RuntimeClient(
      handle = 9L,
      native = native,
      approverClient = testApprovalClient(native),
    )

    val error = assertThrows(RuntimeBridgeException::class.java) { client.close() }
    client.close()

    assertEquals(listOf(10L, 9L), native.closedHandles)
    assertTrue(error.message?.contains("approver close failed") == true)
    assertTrue(error.message?.contains("requester close failed") == true)
  }
}

private fun ownerApprovalPolicy(): RuntimeSkillPolicy =
  RuntimeSkillPolicy(
    mode = "owner_only",
    allowedKinds = listOf("instruction_only", "host_tools_only"),
  )

private fun testSecurityContext(subject: String): RuntimeSecurityContext =
  RuntimeSecurityContext(
    providerId = "agentweave.identity.oidc",
    appId = "com.example.managed",
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

private fun testApprovalClient(
  native: NativeRuntimeApi,
  handle: Long = 10L,
  actorId: String = "approver",
): RuntimeApprovalClient =
  RuntimeApprovalClient(
    handle,
    native,
    RuntimeActorContext(
      actorId = actorId,
      role = "owner",
      grants = listOf("activate", "rollback", "delete_managed", "override_builtin"),
    ),
    ownerApprovalPolicy(),
  )

private class BridgeSkillAssets : SkillAssetSource {
  private val files = mapOf(
    "current" to "current".toByteArray(StandardCharsets.UTF_8),
    "generations/current/skill-bundle.json" to "manifest".toByteArray(StandardCharsets.UTF_8),
    "generations/current/skill-bundle.lock" to "lock".toByteArray(StandardCharsets.UTF_8),
  )

  override fun bundleHash(): String {
    val digest = MessageDigest.getInstance("SHA-256")
    for ((path, bytes) in files.toSortedMap()) {
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

private class RecordingNativeRuntime(
  private val initializeResponse: String = """{"ok":true,"data":{"handle":41}}""",
) : NativeRuntimeApi {
  var initializeRequest: String = ""
  val closedHandles = mutableListOf<Long>()

  override fun initialize(requestJson: String): String {
    initializeRequest = requestJson
    return initializeResponse
  }

  override fun invoke(handle: Long, requestJson: String): String =
    """{"ok":true,"data":null}"""

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
    """{"ok":true,"data":{"assistant_text":"ok"}}"""

  override fun close(handle: Long): String {
    closedHandles += handle
    return """{"ok":true,"data":null}"""
  }
}

private class OwnerNativeRuntime : NativeRuntimeApi {
  constructor(rollbackApproval: Boolean = false) {
    this.rollbackApproval = rollbackApproval
  }

  private var rollbackApproval: Boolean = false
  val requests = mutableListOf<JSONObject>()

  override fun initialize(requestJson: String): String = error("not used")

  override fun invoke(handle: Long, requestJson: String): String {
    val request = JSONObject(requestJson)
    requests += request
    val data = when (request.getString("operation")) {
      "list_managed_skills" -> """[{"package_id":"com.example.owner","display_name":"Owner skill","version":"1.0.0","source_layer":"managed","status":"active","reason":"","active_revision_id":"revision-active","manageable":true}]"""
      "get_skill_detail" -> """{"package_id":"com.example.owner","display_name":"Owner skill","version":"1.0.0","source_layer":"managed","status":"active","reason":"","active_revision_id":"revision-active","revisions":[{"revision_id":"revision-draft","version":"1.1.0","status":"staging","editable":true,"created_by":"owner","created_at":"2026-07-13T00:00:00Z","kind":"host_tools_only","instructions":"Draft instructions","validation":{"ok":true,"errors":[],"warnings":[]},"requirements":{"runtime_tools":["host/search"],"capabilities":["network.http"],"connectors":[],"packages":[]},"permission_diff":{"capabilities":{"added":["network.http"]}}},{"revision_id":"revision-active","version":"1.0.0","status":"managed","editable":false,"created_by":"owner","created_at":"2026-07-12T00:00:00Z","kind":"host_tools_only","instructions":"Active instructions","validation":{"ok":true,"errors":[],"warnings":[]},"requirements":{"runtime_tools":["host/search"],"capabilities":[],"connectors":[],"packages":[]},"permission_diff":{}}],"editable_draft":{"revision_id":"revision-draft","version":"1.1.0","status":"staging","editable":true,"created_by":"owner","created_at":"2026-07-13T00:00:00Z","kind":"host_tools_only","instructions":"Draft instructions","validation":{"ok":true,"errors":[],"warnings":[]},"requirements":{"runtime_tools":["host/search"],"capabilities":["network.http"],"connectors":[],"packages":[]},"permission_diff":{}}}"""
      "create_skill_draft", "update_skill_draft" -> """{"package_id":"com.example.new-skill","revision_id":"revision-draft","version":"0.1.0","kind":"instruction_only","validation":{"status":"pending"},"status":"draft"}"""
      "validate_skill_draft" -> """{"ok":true,"errors":[],"warnings":[],"requiredTools":["host/search"],"requiredConnectors":[],"dependencies":[],"requiredCapabilities":["network.http"],"resolverStatus":"active","resolverErrors":[],"permissionDiff":{"capabilities":{"added":["network.http"]}},"revisionId":"revision-draft","contentHash":"hash","snapshotGeneration":7}"""
      "request_skill_activation", "request_skill_removal" -> """{"approval_id":"approval-1","package_id":"com.example.owner","permission_diff":{},"requested_by":"owner","revision_id":"revision-draft","status":"pending"}"""
      "resolve_skill_approval" -> """{"previous_generation":7,"active_generation":8,"active_packages":1,"inactive_packages":0,"status":"approved"}"""
      "synchronize_skills" -> """{"platform":"android","capabilities":[],"database_ready":true,"skills_ready":true,"model_configured":false,"skill_management_mode":"owner_only","active_snapshot_generation":8,"quarantined_count":0,"last_reload_status":"generation:8"}"""
      "disable_managed_skill" -> """{"previous_generation":8,"active_generation":9,"active_packages":0,"inactive_packages":1}"""
      "rollback_managed_skill" -> if (rollbackApproval) {
        """{"approval_id":"approval-rollback","package_id":"com.example.owner","permission_diff":{},"requested_by":"mobile-requester","revision_id":"revision-old","status":"pending"}"""
      } else {
        """{"package_id":"com.example.owner","active_revision_id":"revision-active","replaced_revision_id":"revision-new","generation":10}"""
      }
      else -> error("unexpected operation")
    }
    return """{"ok":true,"data":$data}"""
  }

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String =
    error("not used")

  override fun close(handle: Long): String = """{"ok":true,"data":null}"""
}

private class MultiHandleNativeRuntime : NativeRuntimeApi {
  val initializeActors = mutableListOf<String>()
  val invokeHandles = mutableListOf<Long>()
  private var nextHandle = 100L

  override fun initialize(requestJson: String): String {
    initializeActors += JSONObject(requestJson).getJSONObject("actor_context").getString("actor_id")
    nextHandle += 1
    return """{"ok":true,"data":{"handle":$nextHandle}}"""
  }

  override fun invoke(handle: Long, requestJson: String): String {
    invokeHandles += handle
    return if (JSONObject(requestJson).getString("operation") == "synchronize_skills") {
      """{"ok":true,"data":{"platform":"android","capabilities":[],"database_ready":true,"skills_ready":true,"model_configured":false,"skill_management_mode":"owner_only","active_snapshot_generation":8,"quarantined_count":0,"last_reload_status":"generation:8"}}"""
    } else {
      """{"ok":true,"data":{"previous_generation":7,"active_generation":8,"active_packages":1,"inactive_packages":0,"status":"approved"}}"""
    }
  }

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String = error("not used")

  override fun close(handle: Long): String = """{"ok":true,"data":null}"""
}

private class SynchronizationFailureNativeRuntime(
  private val recoverySucceeds: Boolean = true,
) : NativeRuntimeApi {
  val operations = mutableListOf<String>()
  private var synchronizationAttempts = 0

  override fun initialize(requestJson: String): String = error("not used")

  override fun invoke(handle: Long, requestJson: String): String {
    val operation = JSONObject(requestJson).getString("operation")
    operations += operation
    return when (operation) {
      "resolve_skill_approval" ->
        """{"ok":true,"data":{"active_generation":8,"status":"approved"}}"""
      "synchronize_skills" ->
        if (handle == 9L && (++synchronizationAttempts == 1 || !recoverySucceeds)) {
          """{"ok":false,"error":{"code":"runtime_error","message":"requester synchronization failed"}}"""
        } else {
          """{"ok":true,"data":{"platform":"android","capabilities":[],"database_ready":true,"skills_ready":true,"model_configured":false,"skill_management_mode":"owner_only","active_snapshot_generation":8,"quarantined_count":0,"last_reload_status":"generation:8"}}"""
        }
      "list_skills" -> """{"ok":true,"data":[]}"""
      else -> error("unexpected operation: $operation")
    }
  }

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String = error("not used")

  override fun close(handle: Long): String = """{"ok":true,"data":null}"""
}

private class FailingCloseNativeRuntime : NativeRuntimeApi {
  val closedHandles = mutableListOf<Long>()

  override fun initialize(requestJson: String): String = error("not used")

  override fun invoke(handle: Long, requestJson: String): String = error("not used")

  override fun sendMessage(handle: Long, requestJson: String, apiKey: String?): String = error("not used")

  override fun close(handle: Long): String {
    closedHandles += handle
    val actor = if (handle == 10L) "approver" else "requester"
    return """{"ok":false,"error":{"code":"close_failed","message":"$actor close failed"}}"""
  }
}

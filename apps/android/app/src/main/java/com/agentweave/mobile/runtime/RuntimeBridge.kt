package com.agentweave.mobile.runtime

import android.content.Context
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

class RuntimeBridge(
  private val context: Context,
  private val native: NativeRuntimeApi = NativeRuntime,
  private val skillAssets: SkillAssetSource = AndroidSkillAssetSource(context.assets),
  private val configuredSkillPolicy: RuntimeSkillPolicy = RuntimeSkillPolicy(),
  private val configuredActorContext: RuntimeActorContext = RuntimeActorContext(),
  private val publicationFileSystem: SkillPublicationFileSystem = AndroidSkillPublicationFileSystem(),
  private val configuredApproverContext: RuntimeActorContext? = null,
  private val configuredSecurityContext: RuntimeSecurityContext? = null,
  private val configuredGatewayCredentialProvider: RuntimeGatewayCredentialProvider? = null,
) {
  fun initRequest(
    actorContext: RuntimeActorContext = configuredActorContext,
    securityContext: RuntimeSecurityContext? = configuredSecurityContext,
  ): RuntimeInitRequest {
    val filesDir = context.filesDir
    val installedBundle = SkillAssetInstaller(filesDir, skillAssets, publicationFileSystem).installVerifiedBundle()
    val installedApp = AgentAppAssetInstaller(
      filesDir,
      AndroidAgentAppAssetSource(context.assets),
    ).install()
    return RuntimeInitRequest(
      appDataDir = filesDir.absolutePath,
      appPackageDir = installedApp?.absolutePath,
      cacheDir = context.cacheDir.absolutePath,
      databasePath = filesDir.resolve("agentweave.db").absolutePath,
      builtinSkillsDir = installedBundle.root.absolutePath,
      managedSkillsDir = filesDir.resolve("managed-skills").absolutePath,
      stagingSkillsDir = context.cacheDir.resolve("skill-staging").absolutePath,
      quarantineSkillsDir = filesDir.resolve("skill-quarantine").absolutePath,
      skillPolicy = configuredSkillPolicy,
      actorContext = actorContext,
      securityContext = securityContext,
    )
  }

  fun load(
    securityContext: RuntimeSecurityContext? = configuredSecurityContext,
    gatewayCredentialProvider: RuntimeGatewayCredentialProvider? = configuredGatewayCredentialProvider,
  ): RuntimeClient {
    val response = native.initialize(initRequest(securityContext = securityContext).toJson().toString())
    var allocatedHandle: Long? = null
    var approverHandle: Long? = null
    try {
      val envelope = responseEnvelope(response)
      val data = envelope.getJSONObject("data")
      allocatedHandle = data.getLong("handle")
      check(envelope.keys().asSequence().toSet() == setOf("ok", "data")) {
        "Runtime initialization envelope contains unexpected fields"
      }
      check(data.keys().asSequence().toSet() == setOf("handle")) {
        "Runtime initialization data contains unexpected fields"
      }
      val approverClient = configuredApproverContext?.let { approver ->
        val approverEnvelope = responseEnvelope(
          native.initialize(initRequest(approver, securityContext).toJson().toString()),
        )
        approverHandle = approverEnvelope.getJSONObject("data").getLong("handle")
        RuntimeApprovalClient(checkNotNull(approverHandle), native, approver, configuredSkillPolicy)
      }
      return RuntimeClient(
        handle = allocatedHandle,
        native = native,
        skillGrants = configuredActorContext.grants.toSet(),
        actorContext = configuredActorContext,
        skillPolicy = configuredSkillPolicy,
        approverClient = approverClient,
        securityContext = securityContext,
        gatewayCredentialProvider = gatewayCredentialProvider,
      )
    } catch (error: Exception) {
      approverHandle?.let { handle -> runCatching { responseEnvelope(native.close(handle)) } }
      allocatedHandle?.let { handle -> runCatching { responseEnvelope(native.close(handle)) } }
      if (error is RuntimeBridgeException) throw error
      throw RuntimeBridgeException(error.message ?: "Runtime initialization response is invalid")
    }
  }
}

class RuntimeClient internal constructor(
  val handle: Long,
  private val native: NativeRuntimeApi,
  val skillGrants: Set<String> = emptySet(),
  val actorContext: RuntimeActorContext = RuntimeActorContext(),
  val skillPolicy: RuntimeSkillPolicy = RuntimeSkillPolicy(),
  private val approverClient: RuntimeApprovalClient? = null,
  val securityContext: RuntimeSecurityContext? = null,
  val gatewayCredentialProvider: RuntimeGatewayCredentialProvider? = null,
) : AutoCloseable {
  private val closed = AtomicBoolean(false)
  val approverAccess: RuntimeApproverAccess? get() = approverClient?.access
  val approverActorId: String? get() = approverClient?.actorId
  val approvalAvailable: Boolean
    get() = approverClient != null && approverClient.actorId != actorContext.actorId
  val approvalUnavailableReason: String?
    get() = if (approvalAvailable) null else "A distinct approving actor is unavailable"

  fun approvalAuthority(
    operation: RuntimeSkillApprovalOperation,
    packageId: String,
    kind: String,
    overrideRequired: Boolean,
  ): RuntimeApprovalAuthority {
    val access = approverAccess
      ?: return RuntimeApprovalAuthority(false, "A distinct approving actor is unavailable")
    val actor = access.actorContext
    val policy = access.skillPolicy
    if (actor.actorId == actorContext.actorId) {
      return RuntimeApprovalAuthority(false, "A distinct approving actor is required")
    }
    if (policy.mode != "owner_only" || actor.role != "owner") {
      return RuntimeApprovalAuthority(false, "Approving actor must have the owner role")
    }
    if (kind !in policy.allowedKinds) {
      return RuntimeApprovalAuthority(false, "Package kind is not allowed for the approving actor")
    }
    if (operation.requiredGrant !in actor.grants) {
      return RuntimeApprovalAuthority(false, "Approving actor lacks ${operation.requiredGrant} grant")
    }
    if (overrideRequired && (
      packageId !in policy.allowedOverrides || "override_builtin" !in actor.grants
    )) {
      return RuntimeApprovalAuthority(false, "Approving actor lacks override authority for this package")
    }
    return RuntimeApprovalAuthority(true)
  }

  fun diagnostics(): RuntimeDiagnostics =
    invoke(JSONObject().put("operation", "diagnostics")).toDiagnostics()

  fun synchronizeSkills(): RuntimeDiagnostics =
    invoke(JSONObject().put("operation", "synchronize_skills")).toDiagnostics()

  fun createSession(title: String): RuntimeSession =
    invoke(JSONObject().put("operation", "create_session").put("title", title)).toSession()

  fun listSessions(): List<RuntimeSession> =
    invokeArray(JSONObject().put("operation", "list_sessions")).objects().map { it.toSession() }

  fun listSkills(): List<RuntimeSkill> =
    invokeArray(JSONObject().put("operation", "list_skills")).objects().map { it.toSkill() }

  fun listManagedSkills(): List<RuntimeSkillPackageSummary> =
    invokeArray(JSONObject().put("operation", "list_managed_skills"))
      .objects()
      .map { it.toSkillPackageSummary() }

  fun getSkillDetail(packageId: String): RuntimeSkillDetail =
    invoke(
      JSONObject()
        .put("operation", "get_skill_detail")
        .put("package_id", packageId),
    ).toSkillDetail()

  fun createSkillDraft(request: RuntimeSkillDraftRequest): RuntimeSkillDraftSummary =
    invoke(
      JSONObject()
        .put("operation", "create_skill_draft")
        .put("request", request.toJson())
        .put("files", JSONArray(request.initialFiles.map { it.toJson() })),
    ).toSkillDraftSummary()

  fun updateSkillDraft(
    revisionId: String,
    files: List<RuntimeSkillDraftFile>,
  ): RuntimeSkillDraftSummary =
    invoke(
      JSONObject()
        .put("operation", "update_skill_draft")
        .put("revision_id", revisionId)
        .put("files", JSONArray(files.map { it.toJson() })),
    ).toSkillDraftSummary()

  fun validateSkillDraft(revisionId: String): RuntimeSkillValidation =
    invoke(
      JSONObject()
        .put("operation", "validate_skill_draft")
        .put("revision_id", revisionId),
    ).toSkillValidation()

  fun requestSkillActivation(revisionId: String): RuntimeSkillApproval =
    invoke(
      JSONObject()
        .put("operation", "request_skill_activation")
        .put("revision_id", revisionId),
    ).toSkillApproval()

  fun resolveSkillApproval(approvalId: String, approve: Boolean): RuntimeSkillApprovalResolution {
    val approval = if (approvalAvailable) approverClient else null
    if (approval == null) {
      throw RuntimeBridgeException(approvalUnavailableReason ?: "Approval resolution is unavailable")
    }
    approval.synchronize()
    val mutation = approval.resolve(
      JSONObject()
        .put("operation", "resolve_skill_approval")
        .put("approval_id", approvalId)
        .put("approve", approve),
    ).toSkillMutation()
    val synchronizationWarning = runCatching { synchronizeSkills() }.exceptionOrNull()?.let { error ->
      error.message ?: "Requester synchronization failed"
    }
    return RuntimeSkillApprovalResolution(mutation, synchronizationWarning)
  }

  fun disableManagedSkill(packageId: String): RuntimeSkillMutation =
    invoke(
      JSONObject()
        .put("operation", "disable_managed_skill")
        .put("package_id", packageId),
    ).toSkillMutation()

  fun rollbackManagedSkill(packageId: String, revisionId: String): RuntimeSkillRollbackOutcome {
    val data = invoke(
      JSONObject()
        .put("operation", "rollback_managed_skill")
        .put("package_id", packageId)
        .put("revision_id", revisionId),
    )
    return if (data.has("approval_id")) {
      RuntimeSkillRollbackOutcome.ApprovalRequired(data.toSkillApproval())
    } else {
      RuntimeSkillRollbackOutcome.Published(data.toSkillMutation())
    }
  }

  fun requestSkillRemoval(packageId: String): RuntimeSkillApproval =
    invoke(
      JSONObject()
        .put("operation", "request_skill_removal")
        .put("package_id", packageId),
    ).toSkillApproval()

  fun getMessages(sessionId: String): List<RuntimeMessage> =
    invokeArray(
      JSONObject().put("operation", "get_messages").put("session_id", sessionId),
    ).objects().map { it.toMessage() }

  fun deleteSession(sessionId: String) {
    invokeUnit(JSONObject().put("operation", "delete_session").put("session_id", sessionId))
  }

  fun saveModelConfig(config: RuntimeModelConfig) {
    invokeUnit(JSONObject().put("operation", "save_model_config").put("config", config.toJson()))
  }

  fun loadModelConfig(): RuntimeModelConfig? {
    val envelope = responseEnvelope(
      native.invoke(handle, JSONObject().put("operation", "load_model_config").toString()),
    )
    val data = envelope.opt("data")
    return if (data == null || data == JSONObject.NULL) null else (data as JSONObject).toModelConfig()
  }

  fun refreshSecurityContext(securityContext: RuntimeSecurityContext) {
    invokeUnit(
      JSONObject()
        .put("operation", "refresh_security_context")
        .put("security_context", securityContext.toJson()),
    )
  }

  fun listMemories(query: String = "", limit: Int = 50): List<RuntimeMemory> =
    invokeArray(
      JSONObject()
        .put("operation", "list_memories")
        .put("query", query)
        .put("limit", limit),
    ).objects().map { it.toMemory() }

  fun forgetMemory(memoryId: String, expectedVersion: Long) {
    invoke(
      JSONObject()
        .put("operation", "forget_memory")
        .put("memory_id", memoryId)
        .put("expected_version", expectedVersion),
    )
  }

  fun exportMemories(): String =
    invoke(JSONObject().put("operation", "export_memories")).toString(2)

  fun listMailAccounts(): List<RuntimeMailAccount> =
    invokeArray(JSONObject().put("operation", "list_mail_accounts"))
      .objects()
      .map { it.toMailAccount() }

  fun mailAccountStatus(accountId: String): RuntimeMailAccountStatus =
    invoke(
      JSONObject()
        .put("operation", "mail_account_status")
        .put("account_id", accountId),
    ).toMailAccountStatus()

  fun connectMailAccount(accountId: String): RuntimeMailAccountStatus =
    invoke(
      JSONObject()
        .put("operation", "connect_mail_account")
        .put("account_id", accountId),
    ).toMailAccountStatus()

  fun disconnectMailAccount(accountId: String): RuntimeMailAccountStatus =
    invoke(
      JSONObject()
        .put("operation", "disconnect_mail_account")
        .put("account_id", accountId),
    ).toMailAccountStatus()

  fun listFoundationActions(): List<RuntimePendingFoundationAction> =
    invokeArray(JSONObject().put("operation", "list_foundation_actions"))
      .objects()
      .map { it.toPendingFoundationAction() }

  fun resolveFoundationAction(
    approvalId: String,
    approve: Boolean,
  ): RuntimeFoundationActionResolution =
    invoke(
      JSONObject()
        .put("operation", "resolve_foundation_action")
        .put("approval_id", approvalId)
        .put("decision", if (approve) "approve_once" else "reject"),
    ).toFoundationActionResolution()

  fun runSchedulerTick(limit: Int = 25): Int =
    invokeValue(
      JSONObject()
        .put("operation", "run_scheduler_tick")
        .put("limit", limit),
    ) as Int

  fun claimNotifications(worker: String, limit: Int = 25): List<RuntimeNotification> =
    invokeArray(
      JSONObject()
        .put("operation", "claim_notifications")
        .put("worker", worker)
        .put("limit", limit),
    ).objects().map { it.toRuntimeNotification() }

  fun finishNotificationDelivered(
    notificationId: String,
    worker: String,
    deliveryId: String,
  ): Boolean =
    invokeValue(
      JSONObject()
        .put("operation", "finish_notification")
        .put("notification_id", notificationId)
        .put("worker", worker)
        .put(
          "outcome",
          JSONObject()
            .put("kind", "delivered")
            .put("delivery_id", deliveryId),
        ),
    ) as Boolean

  fun finishNotificationUncertain(
    notificationId: String,
    worker: String,
    message: String,
  ): Boolean =
    invokeValue(
      JSONObject()
        .put("operation", "finish_notification")
        .put("notification_id", notificationId)
        .put("worker", worker)
        .put(
          "outcome",
          JSONObject()
            .put("kind", "uncertain")
            .put("message", message),
        ),
    ) as Boolean

  fun sendMessage(sessionId: String, content: String, apiKey: String?): RuntimeTurn {
    val request = JSONObject().put("session_id", sessionId).put("content", content)
    val data = responseData(native.sendMessage(handle, request.toString(), apiKey))
    return RuntimeTurn(data.getString("assistant_text"))
  }

  override fun close() {
    if (closed.compareAndSet(false, true)) {
      val errors = mutableListOf<String>()
      approverClient?.let { approver ->
        runCatching { approver.close() }
          .exceptionOrNull()
          ?.let { errors += it.message ?: "approver close failed" }
      }
      runCatching { responseEnvelope(native.close(handle)) }
        .exceptionOrNull()
        ?.let { errors += it.message ?: "requester close failed" }
      if (errors.isNotEmpty()) {
        throw RuntimeBridgeException("Runtime close failed: ${errors.joinToString("; ")}")
      }
    }
  }

  private fun invoke(request: JSONObject): JSONObject = responseData(native.invoke(handle, request.toString()))

  private fun invokeValue(request: JSONObject): Any =
    responseEnvelope(native.invoke(handle, request.toString())).get("data")

  private fun invokeUnit(request: JSONObject) {
    responseEnvelope(native.invoke(handle, request.toString()))
  }

  private fun invokeArray(request: JSONObject): JSONArray =
    responseEnvelope(native.invoke(handle, request.toString())).getJSONArray("data")
}

class RuntimeApprovalClient internal constructor(
  val handle: Long,
  private val native: NativeRuntimeApi,
  actorContext: RuntimeActorContext,
  skillPolicy: RuntimeSkillPolicy,
) : AutoCloseable {
  private val closed = AtomicBoolean(false)
  val access = RuntimeApproverAccess(actorContext, skillPolicy)
  val actorId: String get() = access.actorContext.actorId

  internal fun synchronize() {
    responseData(native.invoke(handle, JSONObject().put("operation", "synchronize_skills").toString()))
  }

  internal fun resolve(request: JSONObject): JSONObject =
    responseData(native.invoke(handle, request.toString()))

  override fun close() {
    if (closed.compareAndSet(false, true)) responseEnvelope(native.close(handle))
  }
}

class RuntimeBridgeException(message: String) : IllegalStateException(message)

private fun RuntimeInitRequest.toJson(): JSONObject =
  JSONObject()
    .put("app_data_dir", appDataDir)
    .put("app_package_dir", appPackageDir)
    .put("cache_dir", cacheDir)
    .put("database_path", databasePath)
    .put("builtin_skills_dir", builtinSkillsDir)
    .put("managed_skills_dir", managedSkillsDir)
    .put("staging_skills_dir", stagingSkillsDir)
    .put("quarantine_skills_dir", quarantineSkillsDir)
    .put("skill_policy", skillPolicy.toJson())
    .put("actor_context", actorContext.toJson())
    .put("platform", platform)
    .put("capabilities", JSONArray(capabilities))
    .put("security_context", securityContext?.toJson() ?: JSONObject.NULL)

private fun RuntimeSkillPolicy.toJson(): JSONObject =
  JSONObject()
    .put("mode", mode)
    .put("agent_authoring", agentAuthoring)
    .put("allowed_kinds", JSONArray(allowedKinds))
    .put("protected_packages", JSONArray(protectedPackages))
    .put("allowed_overrides", JSONArray(allowedOverrides))
    .put("rollback_approval_required", rollbackApprovalRequired)

private fun RuntimeActorContext.toJson(): JSONObject =
  JSONObject()
    .put("actor_id", actorId)
    .put("role", role)
    .put("tenant_id", tenantId)
    .put("device_id", deviceId)
    .put("grants", JSONArray(grants))

private fun RuntimeSecurityContext.toJson(): JSONObject =
  JSONObject()
    .put("schemaVersion", schemaVersion)
    .put("providerId", providerId)
    .put("appId", appId)
    .put("tenantId", tenantId)
    .put("audience", audience)
    .put(
      "principal",
      JSONObject()
        .put("issuer", principal.issuer)
        .put("subject", principal.subject),
    )
    .put("grantedScopes", JSONArray(grantedScopes))
    .put("authenticatedAt", authenticatedAt)
    .put("expiresAt", expiresAt)

private fun RuntimeModelConfig.toJson(): JSONObject =
  JSONObject()
    .put("provider_id", providerId)
    .put("provider_name", providerName)
    .put("endpoint_type", endpointType)
    .put("base_url", baseUrl)
    .put("model_name", modelName)
    .put("secret_id", secretId)
    .put("headers", JSONObject(headers))

private fun RuntimeSkillDraftRequest.toJson(): JSONObject =
  JSONObject()
    .put("package_id", packageId)
    .put("display_name", displayName)
    .put("description", description)
    .put("kind", kind)
    .put("required_tools", JSONArray(requiredTools))

private fun RuntimeSkillDraftFile.toJson(): JSONObject =
  JSONObject()
    .put("path", path)
    .put("content", content)

private fun responseEnvelope(response: String): JSONObject {
  val envelope = JSONObject(response)
  if (!envelope.optBoolean("ok")) {
    throw RuntimeBridgeException(envelope.optJSONObject("error")?.optString("message") ?: "Runtime call failed")
  }
  return envelope
}

private fun responseData(response: String): JSONObject = responseEnvelope(response).getJSONObject("data")

private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

private fun JSONObject.toSession(): RuntimeSession =
  RuntimeSession(
    id = getString("id"),
    title = getString("title"),
    createdAt = getString("created_at"),
    updatedAt = getString("updated_at"),
  )

private fun JSONObject.toMessage(): RuntimeMessage =
  RuntimeMessage(
    id = getString("id"),
    sessionId = getString("session_id"),
    role = getString("role"),
    content = getString("content"),
    createdAt = getString("created_at"),
  )

private fun JSONObject.toDiagnostics(): RuntimeDiagnostics =
  RuntimeDiagnostics(
    appId = optString("app_id", "dev.agentweave.default"),
    appVersion = optString("app_version", "0.1.0"),
    appDisplayName = optString("app_display_name", "AgentWeave"),
    platform = getString("platform"),
    capabilities = getJSONArray("capabilities").strings(),
    databaseReady = getBoolean("database_ready"),
    skillsReady = getBoolean("skills_ready"),
    modelConfigured = getBoolean("model_configured"),
    skillManagementMode = optString("skill_management_mode", "disabled"),
    activeSnapshotGeneration = optLong("active_snapshot_generation", 0L),
    quarantinedCount = optInt("quarantined_count", 0),
    lastReloadStatus = optString("last_reload_status", "not_loaded"),
    modelConfigurationPolicy = optString("model_configuration_policy", "user_configurable"),
    identityMode = optString("identity_mode", "local_single_user"),
    accountId = if (isNull("account_id")) null else optString("account_id").takeIf(String::isNotEmpty),
  )

private fun JSONObject.toSkill(): RuntimeSkill =
  RuntimeSkill(
    packageId = getString("package_id"),
    displayName = getString("display_name"),
    version = getString("version"),
    sourceLayer = getString("source_layer"),
    status = getString("status"),
    available = getBoolean("available"),
    reason = getString("reason"),
    activeRevisionId = if (isNull("active_revision_id")) null else getString("active_revision_id"),
    manageable = getBoolean("manageable"),
    description = optString("description"),
    builtInCollision = optBoolean("built_in_collision", false),
    effective = optJSONObject("effective")?.toSkillPackageSummary(),
    managed = optJSONObject("managed")?.toSkillPackageSummary(),
    actions = optJSONObject("actions")?.toSkillActions() ?: RuntimeSkillActions(),
  )

private fun JSONObject.toSkillPackageSummary(): RuntimeSkillPackageSummary =
  RuntimeSkillPackageSummary(
    packageId = getString("package_id"),
    displayName = getString("display_name"),
    version = getString("version"),
    sourceLayer = getString("source_layer"),
    status = getString("status"),
    reason = getString("reason"),
    activeRevisionId = nullableString("active_revision_id"),
    manageable = optBoolean("manageable", false),
    available = optBoolean("available", false),
    contentHash = nullableString("content_hash"),
  )

private fun JSONObject.toSkillActions(): RuntimeSkillActions =
  RuntimeSkillActions(
    canEditDraft = optBoolean("can_edit_draft"),
    canValidateDraft = optBoolean("can_validate_draft"),
    canRequestActivation = optBoolean("can_request_activation"),
    canDisable = optBoolean("can_disable"),
    canRequestRemoval = optBoolean("can_request_removal"),
    canRollback = optBoolean("can_rollback"),
  )

private fun JSONObject.toSkillDetail(): RuntimeSkillDetail =
  RuntimeSkillDetail(
    packageId = getString("package_id"),
    displayName = getString("display_name"),
    version = getString("version"),
    sourceLayer = getString("source_layer"),
    status = getString("status"),
    reason = getString("reason"),
    activeRevisionId = nullableString("active_revision_id"),
    revisions = getJSONArray("revisions").objects().map { it.toSkillRevision() },
    editableDraft = optJSONObject("editable_draft")?.toSkillRevision(),
    builtInCollision = optBoolean("built_in_collision", false),
    effective = optJSONObject("effective")?.toSkillPackageSummary(),
    managed = optJSONObject("managed")?.toSkillPackageSummary(),
    actions = optJSONObject("actions")?.toSkillActions() ?: RuntimeSkillActions(),
  )

private fun JSONObject.toSkillRevision(): RuntimeSkillRevision {
  val validation = getJSONObject("validation")
  val requirements = getJSONObject("requirements")
  return RuntimeSkillRevision(
    revisionId = getString("revision_id"),
    version = getString("version"),
    status = getString("status"),
    editable = getBoolean("editable"),
    createdBy = getString("created_by"),
    createdAt = getString("created_at"),
    kind = getString("kind"),
    instructions = getString("instructions"),
    validation = RuntimeSkillValidationSummary(
      ok = validation.optBoolean("ok"),
      errors = validation.stringList("errors"),
      warnings = validation.stringList("warnings"),
    ),
    requirements = RuntimeSkillRequirements(
      runtimeTools = requirements.stringList("runtime_tools"),
      capabilities = requirements.stringList("capabilities"),
      connectors = requirements.stringList("connectors"),
      packages = requirements.stringList("packages"),
    ),
    permissionDiffJson = optJSONObject("permission_diff")?.toString() ?: "{}",
    contentHash = optString("content_hash"),
  )
}

private fun JSONObject.toSkillDraftSummary(): RuntimeSkillDraftSummary =
  RuntimeSkillDraftSummary(
    packageId = getString("package_id"),
    revisionId = getString("revision_id"),
    version = getString("version"),
    kind = getString("kind"),
    status = getString("status"),
  )

private fun JSONObject.toSkillValidation(): RuntimeSkillValidation =
  RuntimeSkillValidation(
    ok = getBoolean("ok"),
    errors = stringList("errors"),
    warnings = stringList("warnings"),
    requiredTools = stringList("requiredTools"),
    requiredConnectors = stringList("requiredConnectors"),
    dependencies = stringList("dependencies"),
    requiredCapabilities = stringList("requiredCapabilities"),
    resolverStatus = getString("resolverStatus"),
    resolverErrors = stringList("resolverErrors"),
    permissionDiffJson = optJSONObject("permissionDiff")?.toString() ?: "{}",
    revisionId = getString("revisionId"),
    contentHash = getString("contentHash"),
    snapshotGeneration = getLong("snapshotGeneration"),
  )

private fun JSONObject.toSkillApproval(): RuntimeSkillApproval =
  RuntimeSkillApproval(
    approvalId = getString("approval_id"),
    packageId = getString("package_id"),
    permissionDiffJson = optJSONObject("permission_diff")?.toString() ?: "{}",
    requestedBy = getString("requested_by"),
    revisionId = getString("revision_id"),
    status = getString("status"),
  )

private fun JSONObject.toSkillMutation(): RuntimeSkillMutation =
  RuntimeSkillMutation(
    approvalId = nullableString("approval_id"),
    packageId = nullableString("package_id"),
    revisionId = nullableString("revision_id") ?: nullableString("active_revision_id"),
    status = optString("status", "published"),
    activeGeneration = when {
      has("active_generation") -> getLong("active_generation")
      has("generation") -> getLong("generation")
      else -> 0L
    },
  )

private fun JSONObject.stringList(key: String): List<String> =
  optJSONArray(key)?.strings() ?: emptyList()

private fun JSONObject.nullableString(key: String): String? =
  if (!has(key) || isNull(key)) null else getString(key)

private fun JSONObject.toModelConfig(): RuntimeModelConfig =
  RuntimeModelConfig(
    providerId = getString("provider_id"),
    providerName = getString("provider_name"),
    endpointType = getString("endpoint_type"),
    baseUrl = getString("base_url"),
    modelName = getString("model_name"),
    secretId = if (isNull("secret_id")) null else getString("secret_id"),
    headers = getJSONObject("headers").keys().asSequence().associateWith { key ->
      getJSONObject("headers").getString(key)
    },
  )

private fun JSONObject.toMemory(): RuntimeMemory {
  val value = getJSONObject("value")
  val retention = getJSONObject("retention")
  val attributes = value.getJSONObject("attributes")
  return RuntimeMemory(
    id = getString("id"),
    kind = getString("kind"),
    text = value.getString("text"),
    attributes = attributes.keys().asSequence().associateWith(attributes::getString),
    evidence = getJSONArray("evidence").objects().map { evidence ->
      RuntimeMemoryEvidence(
        source = evidence.getString("source"),
        sourceId = evidence.nullableString("sourceId"),
        excerpt = evidence.nullableString("excerpt"),
        observedAt = evidence.getString("observedAt"),
      )
    },
    confidence = getInt("confidence"),
    sensitivity = getString("sensitivity"),
    retention = retention.getString("mode"),
    state = getString("state"),
    version = getLong("version"),
    updatedAt = getString("updatedAt"),
  )
}

private fun JSONObject.toMailAddress(): RuntimeMailAddress =
  RuntimeMailAddress(
    name = nullableString("name"),
    address = getString("address"),
  )

private fun JSONObject.toMailAccount(): RuntimeMailAccount =
  RuntimeMailAccount(
    id = getString("id"),
    displayName = getString("displayName"),
    primaryAddress = getJSONObject("primaryAddress").toMailAddress(),
    addresses = getJSONArray("addresses").objects().map { it.toMailAddress() },
  )

private fun JSONObject.toMailAccountStatus(): RuntimeMailAccountStatus =
  RuntimeMailAccountStatus(
    account = getJSONObject("account").toMailAccount(),
    state = getString("state"),
    detail = nullableString("detail"),
  )

private fun JSONObject.toMailPreview(): RuntimeMailPreview =
  RuntimeMailPreview(
    id = getString("id"),
    accountId = getString("accountId"),
    draftId = getString("draftId"),
    draftRevision = getLong("draftRevision"),
    from = getJSONObject("from").toMailAddress(),
    to = getJSONArray("to").objects().map { it.toMailAddress() },
    cc = getJSONArray("cc").objects().map { it.toMailAddress() },
    bcc = getJSONArray("bcc").objects().map { it.toMailAddress() },
    subject = getString("subject"),
    previewHash = getString("previewHash"),
    attachmentCount = getJSONArray("attachments").length(),
  )

private fun JSONObject.toFoundationApproval(): RuntimeFoundationApproval {
  val binding = getJSONObject("binding")
  return RuntimeFoundationApproval(
    approvalId = getString("approval_id"),
    status = getString("status"),
    actionName = binding.getString("action_name"),
    resourceTarget = binding.getString("resource_target"),
    riskSummary = binding.getString("risk_summary"),
    argumentsSha256 = binding.getString("arguments_sha256"),
  )
}

private fun JSONObject.toFoundationAction(): RuntimeFoundationAction =
  RuntimeFoundationAction(
    actionId = getString("action_id"),
    status = getString("status"),
    lastError = nullableString("last_error"),
    resultJson = opt("result")?.takeUnless { it == JSONObject.NULL }?.toString(),
  )

private fun JSONObject.toPendingFoundationAction(): RuntimePendingFoundationAction =
  RuntimePendingFoundationAction(
    approval = getJSONObject("approval").toFoundationApproval(),
    action = getJSONObject("action").toFoundationAction(),
    preview = optJSONObject("preview")?.toMailPreview(),
  )

private fun JSONObject.toFoundationActionResolution(): RuntimeFoundationActionResolution =
  RuntimeFoundationActionResolution(
    approval = getJSONObject("approval").toFoundationApproval(),
    action = getJSONObject("action").toFoundationAction(),
  )

private fun JSONObject.toRuntimeNotification(): RuntimeNotification {
  val request = getJSONObject("request")
  return RuntimeNotification(
    notificationId = getString("notification_id"),
    channel = request.getString("channel"),
    title = request.getString("title"),
    body = request.getString("body"),
    status = getString("status"),
    attemptCount = getInt("attempt_count"),
    dataJson = request.get("data").toString(),
  )
}

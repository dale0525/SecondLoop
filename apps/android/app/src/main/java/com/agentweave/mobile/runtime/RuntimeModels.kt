package com.agentweave.mobile.runtime

data class RuntimePrincipalIdentity(
  val issuer: String,
  val subject: String,
)

/**
 * Verified, non-secret identity facts supplied by the Android identity plugin.
 * Bearer and refresh tokens deliberately have no representation here.
 */
data class RuntimeSecurityContext(
  val schemaVersion: Int = 1,
  val providerId: String,
  val appId: String,
  val tenantId: String,
  val audience: String,
  val principal: RuntimePrincipalIdentity,
  val grantedScopes: List<String>,
  val authenticatedAt: String,
  val expiresAt: String,
)

data class RuntimeGatewayCredential(
  val bearerToken: String,
  val securityContext: RuntimeSecurityContext,
)

fun interface RuntimeGatewayCredentialProvider {
  /** Returns a current short-lived assertion and its verified non-secret context. */
  fun credential(): RuntimeGatewayCredential
}

data class RuntimeInitRequest(
  val appDataDir: String,
  val appPackageDir: String? = null,
  val cacheDir: String,
  val databasePath: String,
  val builtinSkillsDir: String,
  val managedSkillsDir: String,
  val stagingSkillsDir: String,
  val quarantineSkillsDir: String,
  val skillPolicy: RuntimeSkillPolicy,
  val actorContext: RuntimeActorContext,
  val platform: String = "android",
  val capabilities: List<String> = androidMvpCapabilities(),
  val securityContext: RuntimeSecurityContext? = null,
)

data class RuntimeSkillPolicy(
  val mode: String = "disabled",
  val agentAuthoring: Boolean = false,
  val allowedKinds: List<String> = emptyList(),
  val protectedPackages: List<String> = emptyList(),
  val allowedOverrides: List<String> = emptyList(),
  val rollbackApprovalRequired: Boolean = false,
)

data class RuntimeActorContext(
  val actorId: String = "anonymous",
  val role: String = "user",
  val tenantId: String? = null,
  val deviceId: String? = null,
  val grants: List<String> = emptyList(),
)

data class RuntimeDiagnostics(
  val appId: String = "dev.agentweave.default",
  val appVersion: String = "0.1.0",
  val appDisplayName: String = "AgentWeave",
  val platform: String,
  val capabilities: List<String>,
  val databaseReady: Boolean,
  val skillsReady: Boolean,
  val modelConfigured: Boolean,
  val skillManagementMode: String,
  val activeSnapshotGeneration: Long,
  val quarantinedCount: Int,
  val lastReloadStatus: String,
  val modelConfigurationPolicy: String = "user_configurable",
  val identityMode: String = "local_single_user",
  val accountId: String? = null,
)

data class RuntimeSession(
  val id: String,
  val title: String,
  val createdAt: String,
  val updatedAt: String,
)

data class RuntimeMessage(
  val id: String,
  val sessionId: String,
  val role: String,
  val content: String,
  val createdAt: String,
)

data class RuntimeSkill(
  val packageId: String,
  val displayName: String,
  val version: String,
  val sourceLayer: String,
  val status: String,
  val available: Boolean,
  val reason: String,
  val activeRevisionId: String?,
  val manageable: Boolean,
  val description: String = "",
  val builtInCollision: Boolean = false,
  val effective: RuntimeSkillPackageSummary? = null,
  val managed: RuntimeSkillPackageSummary? = null,
  val actions: RuntimeSkillActions = RuntimeSkillActions(),
) {
  val id: String get() = packageId
  val label: String get() = displayName

  constructor(
    id: String,
    label: String,
    description: String,
    available: Boolean,
    reason: String,
  ) : this(
    packageId = id,
    displayName = label,
    version = "",
    sourceLayer = "builtin",
    status = if (available) "active" else "unavailable",
    available = available,
    reason = reason,
    activeRevisionId = null,
    manageable = false,
    description = description,
  )
}

data class RuntimeSkillPackageSummary(
  val packageId: String,
  val displayName: String,
  val version: String,
  val sourceLayer: String,
  val status: String,
  val reason: String,
  val activeRevisionId: String?,
  val manageable: Boolean = false,
  val available: Boolean = false,
  val contentHash: String? = null,
)

data class RuntimeSkillActions(
  val canEditDraft: Boolean = false,
  val canValidateDraft: Boolean = false,
  val canRequestActivation: Boolean = false,
  val canDisable: Boolean = false,
  val canRequestRemoval: Boolean = false,
  val canRollback: Boolean = false,
)

data class RuntimeSkillRequirements(
  val runtimeTools: List<String>,
  val capabilities: List<String>,
  val connectors: List<String>,
  val packages: List<String>,
)

data class RuntimeSkillValidationSummary(
  val ok: Boolean,
  val errors: List<String>,
  val warnings: List<String>,
)

data class RuntimeSkillRevision(
  val revisionId: String,
  val version: String,
  val status: String,
  val editable: Boolean,
  val createdBy: String,
  val createdAt: String,
  val kind: String,
  val instructions: String,
  val validation: RuntimeSkillValidationSummary,
  val requirements: RuntimeSkillRequirements,
  val permissionDiffJson: String,
  val contentHash: String = "",
)

data class RuntimeSkillDetail(
  val packageId: String,
  val displayName: String,
  val version: String,
  val sourceLayer: String,
  val status: String,
  val reason: String,
  val activeRevisionId: String?,
  val revisions: List<RuntimeSkillRevision>,
  val editableDraft: RuntimeSkillRevision?,
  val builtInCollision: Boolean = false,
  val effective: RuntimeSkillPackageSummary? = null,
  val managed: RuntimeSkillPackageSummary? = null,
  val actions: RuntimeSkillActions = RuntimeSkillActions(),
)

data class RuntimeSkillDraftRequest(
  val packageId: String,
  val displayName: String,
  val description: String,
  val kind: String,
  val requiredTools: List<String>,
  val initialFiles: List<RuntimeSkillDraftFile> = emptyList(),
)

data class RuntimeSkillDraftFile(
  val path: String,
  val content: String,
)

data class RuntimeSkillDraftSummary(
  val packageId: String,
  val revisionId: String,
  val version: String,
  val kind: String,
  val status: String,
)

data class RuntimeSkillValidation(
  val ok: Boolean,
  val errors: List<String>,
  val warnings: List<String>,
  val requiredTools: List<String>,
  val requiredConnectors: List<String>,
  val dependencies: List<String>,
  val requiredCapabilities: List<String>,
  val resolverStatus: String,
  val resolverErrors: List<String>,
  val permissionDiffJson: String,
  val revisionId: String,
  val contentHash: String,
  val snapshotGeneration: Long,
)

data class RuntimeSkillApproval(
  val approvalId: String,
  val packageId: String,
  val permissionDiffJson: String,
  val requestedBy: String,
  val revisionId: String,
  val status: String,
)

data class RuntimeSkillMutation(
  val approvalId: String? = null,
  val packageId: String? = null,
  val revisionId: String? = null,
  val status: String = "published",
  val activeGeneration: Long = 0,
) {
  val approvalRequired: Boolean get() = approvalId != null && status == "pending"
}

data class RuntimeSkillApprovalResolution(
  val mutation: RuntimeSkillMutation,
  val synchronizationWarning: String? = null,
)

enum class RuntimeSkillApprovalOperation(val requiredGrant: String) {
  Activation("activate"),
  Rollback("rollback"),
  Removal("delete_managed"),
}

data class RuntimeApproverAccess(
  val actorContext: RuntimeActorContext,
  val skillPolicy: RuntimeSkillPolicy,
)

data class RuntimeApprovalAuthority(
  val available: Boolean,
  val reason: String = "",
)

sealed interface RuntimeSkillRollbackOutcome {
  data class Published(val mutation: RuntimeSkillMutation) : RuntimeSkillRollbackOutcome
  data class ApprovalRequired(val approval: RuntimeSkillApproval) : RuntimeSkillRollbackOutcome
}

data class RuntimeModelConfig(
  val providerId: String,
  val providerName: String,
  val endpointType: String,
  val baseUrl: String,
  val modelName: String,
  val secretId: String?,
  val headers: Map<String, String> = emptyMap(),
)

data class RuntimeTurn(val assistantText: String)

data class RuntimeMemoryEvidence(
  val source: String,
  val sourceId: String?,
  val excerpt: String?,
  val observedAt: String,
)

data class RuntimeMemory(
  val id: String,
  val kind: String,
  val text: String,
  val attributes: Map<String, String>,
  val evidence: List<RuntimeMemoryEvidence>,
  val confidence: Int,
  val sensitivity: String,
  val retention: String,
  val state: String,
  val version: Long,
  val updatedAt: String,
)

data class RuntimeMailAddress(
  val name: String?,
  val address: String,
)

data class RuntimeMailAccount(
  val id: String,
  val displayName: String,
  val primaryAddress: RuntimeMailAddress,
  val addresses: List<RuntimeMailAddress>,
)

data class RuntimeMailAccountStatus(
  val account: RuntimeMailAccount,
  val state: String,
  val detail: String?,
)

data class RuntimeMailPreview(
  val id: String,
  val accountId: String,
  val draftId: String,
  val draftRevision: Long,
  val from: RuntimeMailAddress,
  val to: List<RuntimeMailAddress>,
  val cc: List<RuntimeMailAddress>,
  val bcc: List<RuntimeMailAddress>,
  val subject: String,
  val previewHash: String,
  val attachmentCount: Int,
)

data class RuntimeFoundationApproval(
  val approvalId: String,
  val status: String,
  val actionName: String,
  val resourceTarget: String,
  val riskSummary: String,
  val argumentsSha256: String,
)

data class RuntimeFoundationAction(
  val actionId: String,
  val status: String,
  val lastError: String?,
  val resultJson: String?,
)

data class RuntimePendingFoundationAction(
  val approval: RuntimeFoundationApproval,
  val action: RuntimeFoundationAction,
  val preview: RuntimeMailPreview?,
)

data class RuntimeFoundationActionResolution(
  val approval: RuntimeFoundationApproval,
  val action: RuntimeFoundationAction,
)

data class RuntimeNotification(
  val notificationId: String,
  val channel: String,
  val title: String,
  val body: String,
  val status: String,
  val attemptCount: Int,
  val dataJson: String,
)

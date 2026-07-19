package com.agentweave.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.agentweave.mobile.runtime.RuntimeClient
import com.agentweave.mobile.runtime.AgentAppAppearance
import com.agentweave.mobile.runtime.AgentAppLocalization
import com.agentweave.mobile.runtime.RuntimeDiagnostics
import com.agentweave.mobile.runtime.MobileIdentityStatus
import com.agentweave.mobile.runtime.RuntimeSkill
import com.agentweave.mobile.runtime.RuntimeSkillPackageSummary
import com.agentweave.mobile.runtime.androidMvpCapabilities
import com.agentweave.mobile.secrets.ModelSecretStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class AppTab(val label: String, val translationKey: String) {
  Chat("Chat", "android.nav.chat"),
  Settings("Settings", "android.nav.settings"),
  Foundation("Data", "android.nav.data"),
  Skills("Skills", "android.nav.skills"),
  Diagnostics("Diagnostics", "android.nav.diagnostics"),
}

enum class SkillScreenMode { Hidden, DiagnosticsOnly, OwnerManage }

enum class SkillAction { Create, Edit, Validate, Activate, Disable, Rollback, Delete }

data class SkillAccessState(
  val mode: SkillScreenMode,
  val visibleTabs: List<AppTab>,
  val actions: Set<SkillAction>,
  val allowedKinds: Set<String> = emptySet(),
  val protectedPackages: Set<String> = emptySet(),
  val allowedOverrides: Set<String> = emptySet(),
  val agentAuthoring: Boolean = false,
  val canOverrideProtected: Boolean = false,
)

fun skillScreenMode(mode: String, grants: Set<String>): SkillScreenMode =
  when {
    mode == "disabled" -> SkillScreenMode.Hidden
    mode == "diagnostics_only" -> SkillScreenMode.DiagnosticsOnly
    mode == "owner_only" && "inspect" in grants -> SkillScreenMode.OwnerManage
    else -> SkillScreenMode.Hidden
  }

fun visibleTabs(skillManagementMode: String): List<AppTab> =
  AppTab.entries.filter { tab ->
    tab != AppTab.Skills || skillManagementMode != "disabled"
  }

fun skillActions(mode: SkillScreenMode, grants: Set<String>): Set<SkillAction> {
  if (mode != SkillScreenMode.OwnerManage) return emptySet()
  return buildSet {
    if ("create_draft" in grants) add(SkillAction.Create)
    if ("edit_draft" in grants) add(SkillAction.Edit)
    if ("validate" in grants) add(SkillAction.Validate)
    if ("activate" in grants) add(SkillAction.Activate)
    if ("disable" in grants) add(SkillAction.Disable)
    if ("rollback" in grants) add(SkillAction.Rollback)
    if ("delete_managed" in grants) add(SkillAction.Delete)
  }
}

fun skillAccessState(mode: String, grants: Set<String>): SkillAccessState {
  val screenMode = skillScreenMode(mode, grants)
  val tabs = visibleTabs(mode).filter { tab ->
    tab != AppTab.Skills || screenMode != SkillScreenMode.Hidden
  }
  return SkillAccessState(
    screenMode,
    tabs,
    skillActions(screenMode, grants),
    canOverrideProtected = "override_builtin" in grants,
  )
}

fun admittedPolicyTab(current: AppTab, requested: AppTab, visibleTabs: List<AppTab>): AppTab =
  when {
    requested in visibleTabs -> requested
    current in visibleTabs -> current
    else -> AppTab.Chat
  }

data class NavigationSize(val width: Int, val height: Int)

fun AppTab.activeNavigationSize(): NavigationSize =
  when (this) {
    AppTab.Chat -> NavigationSize(64, 48)
    AppTab.Settings -> NavigationSize(72, 60)
    AppTab.Foundation -> NavigationSize(64, 48)
    AppTab.Skills -> NavigationSize(64, 48)
    AppTab.Diagnostics -> NavigationSize(72, 64)
  }

fun admittedAppTab(current: AppTab, requested: AppTab, settingsSaving: Boolean): AppTab =
  if (settingsSaving) current else requested

data class SkillRow(
  val name: String,
  val detail: String,
  val available: Boolean,
)

fun androidSkillRows(skills: List<RuntimeSkill>): List<SkillRow> =
  skills.map { skill ->
    SkillRow(
      name = skill.label,
      detail = if (skill.available) "Status: Ready" else skill.reason,
      available = skill.available,
    )
  }

fun ownerSkillInventory(
  effective: List<RuntimeSkill>,
  managed: List<RuntimeSkillPackageSummary>,
): List<RuntimeSkill> {
  val inventory = effective.associateByTo(linkedMapOf(), RuntimeSkill::packageId)
  managed.forEach { summary ->
    if (summary.status == "removed") {
      return@forEach
    }
    val effectiveSkill = inventory[summary.packageId]
    inventory[summary.packageId] = if (effectiveSkill != null) {
      effectiveSkill.copy(managed = effectiveSkill.managed ?: summary)
    } else {
      RuntimeSkill(
        packageId = summary.packageId,
        displayName = summary.displayName,
        version = summary.version,
        sourceLayer = summary.sourceLayer,
        status = summary.status,
        available = summary.available,
        reason = summary.reason,
        activeRevisionId = summary.activeRevisionId,
        manageable = summary.manageable,
        managed = summary,
      )
    }
  }
  return inventory.values.sortedBy(RuntimeSkill::packageId)
}

fun androidDiagnosticCapabilityIds(): List<String> = androidMvpCapabilities()

@Composable
fun AppRoot(
  runtimeClient: RuntimeClient,
  turnGate: RuntimeTurnGate,
  settingsGate: RuntimeSettingsGate,
  initialDiagnostics: RuntimeDiagnostics,
  secretStore: ModelSecretStore,
  identityStatus: MobileIdentityStatus? = null,
  onSwitchAccount: () -> Unit = {},
  onSignOut: () -> Unit = {},
  onClearAccountData: () -> Unit = {},
  appearance: AgentAppAppearance,
  selectedThemeId: String,
  localization: AgentAppLocalization,
  selectedLocaleId: String,
  onThemeSelected: (String) -> Unit,
  onLocaleSelected: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  var selectedTab by remember { mutableStateOf(AppTab.Chat) }
  var diagnostics by remember(initialDiagnostics) { mutableStateOf(initialDiagnostics) }
  var skills by remember { mutableStateOf<List<RuntimeSkill>>(emptyList()) }
  var skillLoadError by remember { mutableStateOf<String?>(null) }
  var skillImmersive by remember { mutableStateOf(false) }
  val chatSending by turnGate.inFlight.collectAsState()
  val settingsSaving by settingsGate.inFlight.collectAsState()
  val settingsCompletionVersion by settingsGate.completionVersion.collectAsState()
  val scope = rememberCoroutineScope()
  val skillAccess = skillAccessState(runtimeClient.skillPolicy, runtimeClient.actorContext)

  LaunchedEffect(runtimeClient) {
    try {
      skills = withContext(Dispatchers.IO) {
        runtimeClient.loadSkillInventory()
      }
      skillLoadError = null
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Throwable) {
      skillLoadError = error.message ?: "Managed inventory unavailable"
    }
  }
  LaunchedEffect(skillAccess.visibleTabs) {
    if (selectedTab !in skillAccess.visibleTabs) {
      selectedTab = AppTab.Chat
      skillImmersive = false
    }
  }
  val refreshSkillsAndDiagnostics = {
    scope.launch {
      runCatching {
        withContext(Dispatchers.IO) {
          runtimeClient.loadSkillInventory() to runtimeClient.diagnostics()
        }
      }.onSuccess { refreshed ->
        skills = refreshed.first
        diagnostics = refreshed.second
        skillLoadError = null
      }.onFailure { error ->
        if (error is CancellationException) throw error
        skillLoadError = error.message ?: "Unable to refresh skills"
      }
    }
    Unit
  }

  LaunchedEffect(settingsCompletionVersion) {
    if (settingsCompletionVersion > 0) refreshSkillsAndDiagnostics()
  }

  Column(
    modifier = modifier
      .fillMaxSize()
      .background(GaSurface),
  ) {
    Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
      ChatScreen(
        runtimeClient = runtimeClient,
        turnGate = turnGate,
        diagnostics = diagnostics,
        secretStore = secretStore,
        onRefreshDiagnostics = refreshSkillsAndDiagnostics,
        interactionAllowed = { selectedTab == AppTab.Chat && !settingsSaving },
        modifier = if (selectedTab == AppTab.Chat) {
          Modifier.fillMaxSize().zIndex(1f)
        } else {
          Modifier
            .fillMaxSize()
            .graphicsLayer(alpha = 0f)
            .clearAndSetSemantics { }
            .zIndex(0f)
        },
      )
      if (selectedTab != AppTab.Chat) {
        Box(modifier = Modifier.fillMaxSize().zIndex(1f)) {
          when (selectedTab) {
            AppTab.Chat -> Unit
            AppTab.Settings -> SettingsScreen(
              runtimeClient = runtimeClient,
              secretStore = secretStore,
              modelConfigurationPolicy = diagnostics.modelConfigurationPolicy,
              accountId = diagnostics.accountId,
              identityStatus = identityStatus,
              onSwitchAccount = onSwitchAccount,
              onSignOut = onSignOut,
              onClearAccountData = onClearAccountData,
              settingsGate = settingsGate,
              runtimeBusy = chatSending,
              appearance = appearance,
              selectedThemeId = selectedThemeId,
              localization = localization,
              selectedLocaleId = selectedLocaleId,
              onThemeSelected = onThemeSelected,
              onLocaleSelected = onLocaleSelected,
              onBack = {
                selectedTab = admittedAppTab(selectedTab, AppTab.Chat, settingsSaving)
              },
              onSaved = refreshSkillsAndDiagnostics,
            )
            AppTab.Foundation -> FoundationScreen(
              runtimeClient = runtimeClient,
              appDisplayName = diagnostics.appDisplayName,
            )
            AppTab.Skills -> SkillsScreen(
              mode = skillAccess.mode,
              actions = skillAccess.actions,
              allowedKinds = skillAccess.allowedKinds,
              protectedPackages = skillAccess.protectedPackages,
              allowedOverrides = skillAccess.allowedOverrides,
              agentAuthoring = skillAccess.agentAuthoring,
              canOverrideProtected = skillAccess.canOverrideProtected,
              inventory = skills,
              diagnostics = diagnostics,
              initialError = skillLoadError,
              runtimeClient = runtimeClient,
              onSnapshotChanged = { refreshedSkills, refreshedDiagnostics ->
                skills = refreshedSkills
                diagnostics = refreshedDiagnostics
                skillLoadError = null
              },
              onImmersiveChanged = { skillImmersive = it },
              onBack = { selectedTab = AppTab.Chat },
            )
            AppTab.Diagnostics -> DiagnosticsScreen(
              diagnostics = diagnostics,
              skillRows = androidSkillRows(skills),
              onRefresh = refreshSkillsAndDiagnostics,
            )
          }
        }
      }
    }
    if (!(selectedTab == AppTab.Skills && skillImmersive)) {
      AppBottomNavigation(
        tabs = skillAccess.visibleTabs,
        selected = selectedTab,
        onSelect = { requested ->
          val admitted = admittedPolicyTab(selectedTab, requested, skillAccess.visibleTabs)
          selectedTab = admittedAppTab(selectedTab, admitted, settingsSaving)
        },
      )
    }
  }
}

private fun RuntimeClient.loadSkillInventory(): List<RuntimeSkill> = listSkills()

@Composable
private fun AppBottomNavigation(
  tabs: List<AppTab>,
  selected: AppTab,
  onSelect: (AppTab) -> Unit,
) {
  val strings = LocalAppStrings.current
  NavigationBar(
    modifier = Modifier.fillMaxWidth().height(80.dp),
    containerColor = MaterialTheme.colorScheme.surface,
    tonalElevation = 0.dp,
  ) {
    tabs.forEach { tab ->
      val active = tab == selected
      NavigationBarItem(
        selected = active,
        onClick = { onSelect(tab) },
        icon = {
          Icon(
            imageVector = tab.icon(active),
            contentDescription = null,
            modifier = Modifier.size(24.dp),
          )
        },
        label = {
          Text(
            text = strings.text(tab.translationKey),
            style = MaterialTheme.typography.labelSmall.copy(
              fontSize = 11.sp,
              lineHeight = 16.sp,
              letterSpacing = 0.sp,
            ),
          )
        },
      )
    }
  }
}

private fun AppTab.icon(active: Boolean): ImageVector =
  when (this) {
    AppTab.Chat -> if (active) Icons.AutoMirrored.Filled.Chat else Icons.Outlined.ChatBubbleOutline
    AppTab.Settings -> if (active) Icons.Filled.Settings else Icons.Outlined.Settings
    AppTab.Foundation -> if (active) Icons.Filled.Storage else Icons.Outlined.Storage
    AppTab.Skills -> if (active) Icons.Filled.Extension else Icons.Outlined.Extension
    AppTab.Diagnostics -> if (active) Icons.Filled.Analytics else Icons.Outlined.Analytics
  }

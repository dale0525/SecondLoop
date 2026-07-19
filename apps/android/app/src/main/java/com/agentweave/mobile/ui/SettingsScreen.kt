package com.agentweave.mobile.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.agentweave.mobile.model.ModelSettings
import com.agentweave.mobile.runtime.AgentAppAppearance
import com.agentweave.mobile.runtime.AgentAppLocale
import com.agentweave.mobile.runtime.AgentAppLocalization
import com.agentweave.mobile.runtime.AgentAppTheme
import com.agentweave.mobile.runtime.RuntimeClient
import com.agentweave.mobile.runtime.MobileIdentityStatus
import com.agentweave.mobile.runtime.RuntimeModelConfig
import com.agentweave.mobile.secrets.ModelSecretStore
import com.agentweave.mobile.secrets.ModelSecretStoreException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class ProviderOption(
  val id: String,
  val name: String,
  val label: String,
  val defaultBaseUrl: String,
  val defaultModel: String,
)

private data class EndpointOption(val value: String, val label: String)

private val ProviderOptions = listOf(
  ProviderOption("openai", "OpenAI-compatible", "OpenAI-compatible", "https://api.openai.com/v1", "gpt-5.4"),
  ProviderOption("local", "Local Model", "Local Model", "http://localhost:11434/v1", "qwen2.5"),
)

fun androidProviderIds(): List<String> = ProviderOptions.map { it.id }

fun providerSelectionChanges(currentProviderId: String, selectedProviderId: String): Boolean =
  currentProviderId != selectedProviderId

fun modelSecretReference(providerId: String, accountId: String?): String =
  accountId?.let { "model.$it.$providerId.default" } ?: "model.$providerId.default"

private val EndpointOptions = listOf(
  EndpointOption("responses", "Responses"),
  EndpointOption("chat_completions", "Chat completions"),
  EndpointOption("completion", "Completions"),
)

fun modelSecretReferenceForSave(
  providerId: String,
  currentSecretId: String?,
  hasSavedSecret: Boolean,
  hasNewSecret: Boolean,
  accountId: String? = null,
): String? {
  val providerReference = modelSecretReference(providerId, accountId)
  return when {
    hasNewSecret -> providerReference
    hasSavedSecret && currentSecretId == providerReference -> currentSecretId
    else -> null
  }
}

fun pendingApiKeyForProvider(
  providerId: String,
  pendingProviderId: String?,
  pendingApiKey: String,
): String? = pendingApiKey.trim().takeIf {
  pendingProviderId == providerId && it.isNotEmpty()
}

fun canSaveModelSettings(
  saving: Boolean,
  initialConfigReady: Boolean,
  secretLookupReady: Boolean,
  hasReplacementSecret: Boolean,
  runtimeBusy: Boolean,
): Boolean =
  !saving &&
    initialConfigReady &&
    (secretLookupReady || hasReplacementSecret) &&
    !runtimeBusy

fun isCurrentSecretLookup(
  currentGeneration: Int,
  requestGeneration: Int,
  currentProviderId: String,
  requestProviderId: String,
): Boolean = currentGeneration == requestGeneration && currentProviderId == requestProviderId

data class InitialModelSettings(
  val config: RuntimeModelConfig?,
  val secretSaved: Boolean,
  val secretLookupError: String?,
)

fun loadInitialModelSettings(
  loadConfig: () -> RuntimeModelConfig?,
  secretStore: ModelSecretStore,
): InitialModelSettings {
  val config = loadConfig()
  val secretId = config?.secretId
  if (secretId == null) {
    return InitialModelSettings(config, secretSaved = false, secretLookupError = null)
  }
  return try {
    InitialModelSettings(config, secretStore.loadSecret(secretId) != null, secretLookupError = null)
  } catch (error: ModelSecretStoreException) {
    InitialModelSettings(config, secretSaved = false, secretLookupError = error.message)
  }
}

fun persistModelSettings(
  settings: ModelSettings,
  secretStore: ModelSecretStore,
  saveConfig: (com.agentweave.mobile.runtime.RuntimeModelConfig) -> Unit,
): Boolean {
  val redacted = settings.redactedForRust()
  val newSecret = settings.apiKey?.trim()?.takeIf { it.isNotEmpty() }
  val secretId = redacted.secretId
  val previousSecret = if (newSecret != null && secretId != null) {
    try {
      secretStore.loadSecret(secretId)
    } catch (_: ModelSecretStoreException) {
      secretStore.deleteSecret(secretId)
      null
    }
  } else {
    null
  }

  try {
    if (newSecret != null && secretId != null) {
      secretStore.saveSecret(secretId, newSecret)
    }
    saveConfig(redacted)
  } catch (error: Exception) {
    if (newSecret != null && secretId != null) {
      runCatching {
        if (previousSecret == null) {
          secretStore.deleteSecret(secretId)
        } else {
          secretStore.saveSecret(secretId, previousSecret)
        }
      }.exceptionOrNull()?.let(error::addSuppressed)
    }
    throw error
  }

  return secretId?.let { secretStore.loadSecret(it) != null } ?: false
}

@Composable
fun SettingsScreen(
  runtimeClient: RuntimeClient,
  secretStore: ModelSecretStore,
  modelConfigurationPolicy: String,
  accountId: String?,
  identityStatus: MobileIdentityStatus? = null,
  onSwitchAccount: () -> Unit = {},
  onSignOut: () -> Unit = {},
  onClearAccountData: () -> Unit = {},
  settingsGate: RuntimeSettingsGate,
  runtimeBusy: Boolean,
  appearance: AgentAppAppearance,
  selectedThemeId: String,
  localization: AgentAppLocalization,
  selectedLocaleId: String,
  onThemeSelected: (String) -> Unit,
  onLocaleSelected: (String) -> Unit,
  onBack: () -> Unit,
  onSaved: () -> Unit,
) {
  val strings = LocalAppStrings.current
  val userConfigurable = modelConfigurationPolicy == "user_configurable"
  var provider by remember { mutableStateOf(ProviderOptions.first()) }
  var endpoint by remember { mutableStateOf(EndpointOptions.first()) }
  var baseUrl by remember { mutableStateOf(provider.defaultBaseUrl) }
  var modelName by remember { mutableStateOf(provider.defaultModel) }
  var currentSecretId by remember { mutableStateOf<String?>(null) }
  var hasSavedSecret by remember { mutableStateOf(false) }
  var pendingApiKey by remember { mutableStateOf("") }
  var pendingApiKeyProviderId by remember { mutableStateOf<String?>(null) }
  var dialogApiKey by remember { mutableStateOf("") }
  var secretDialogProviderId by remember { mutableStateOf<String?>(null) }
  var showSecretDialog by remember { mutableStateOf(false) }
  val saving by settingsGate.inFlight.collectAsState()
  var initialConfigReady by remember { mutableStateOf(false) }
  var secretLookupReady by remember { mutableStateOf(false) }
  var secretLookupGeneration by remember { mutableIntStateOf(0) }
  var resultMessage by remember { mutableStateOf<String?>(null) }
  var errorMessage by remember { mutableStateOf<String?>(null) }

  LaunchedEffect(runtimeClient, userConfigurable) {
    try {
      val initialSettings = withContext(Dispatchers.IO) {
        if (userConfigurable) {
          loadInitialModelSettings(runtimeClient::loadModelConfig, secretStore)
        } else {
          InitialModelSettings(
            config = runtimeClient.loadModelConfig(),
            secretSaved = false,
            secretLookupError = null,
          )
        }
      }
      val config = initialSettings.config
      if (config != null) {
        val loadedProvider = ProviderOptions.firstOrNull { it.id == config.providerId }
          ?: ProviderOption(
            config.providerId,
            config.providerName,
            config.providerName,
            config.baseUrl,
            config.modelName,
          )
        if (provider.id != loadedProvider.id) {
          secretLookupReady = false
        }
        provider = loadedProvider
        endpoint = EndpointOptions.firstOrNull { it.value == config.endpointType }
          ?: EndpointOptions.first()
        baseUrl = config.baseUrl
        modelName = config.modelName
        currentSecretId = config.secretId
        hasSavedSecret = initialSettings.secretSaved
      }
      initialSettings.secretLookupError?.let { errorMessage = it }
      initialConfigReady = true
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      errorMessage = error.message ?: "Unable to load model settings"
    }
  }

  LaunchedEffect(provider.id, secretStore, userConfigurable, accountId) {
    if (!userConfigurable) {
      secretLookupReady = true
      return@LaunchedEffect
    }
    val providerId = provider.id
    val reference = modelSecretReference(
      providerId = providerId,
      accountId = accountId,
    )
    val requestGeneration = secretLookupGeneration + 1
    secretLookupGeneration = requestGeneration
    secretLookupReady = false
    try {
      val saved = withContext(Dispatchers.IO) { secretStore.loadSecret(reference) != null }
      if (isCurrentSecretLookup(secretLookupGeneration, requestGeneration, provider.id, providerId)) {
        currentSecretId = reference.takeIf { saved }
        hasSavedSecret = saved
        secretLookupReady = true
      }
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      if (isCurrentSecretLookup(secretLookupGeneration, requestGeneration, provider.id, providerId)) {
        currentSecretId = null
        hasSavedSecret = false
        secretLookupReady = false
        errorMessage = error.message ?: "Unable to load model secret"
      }
    }
  }

  val settingsInteractionAllowed = { initialConfigReady && !saving }
  val hasReplacementSecret = pendingApiKeyForProvider(
    providerId = provider.id,
    pendingProviderId = pendingApiKeyProviderId,
    pendingApiKey = pendingApiKey,
  ) != null

  val saveSettings = {
    val replacementSecretAvailable = pendingApiKeyForProvider(
      providerId = provider.id,
      pendingProviderId = pendingApiKeyProviderId,
      pendingApiKey = pendingApiKey,
    ) != null
    if (
      canSaveModelSettings(
        saving = saving,
        initialConfigReady = initialConfigReady,
        secretLookupReady = secretLookupReady,
        hasReplacementSecret = replacementSecretAvailable,
        runtimeBusy = runtimeBusy,
      ) &&
      settingsGate.tryBegin()
    ) {
      val capturedPendingApiKey = pendingApiKey
      val capturedPendingProviderId = pendingApiKeyProviderId
      val newSecret = pendingApiKeyForProvider(
        providerId = provider.id,
        pendingProviderId = capturedPendingProviderId,
        pendingApiKey = capturedPendingApiKey,
      )
      val secretId = modelSecretReferenceForSave(
        providerId = provider.id,
        currentSecretId = currentSecretId,
        hasSavedSecret = hasSavedSecret,
        hasNewSecret = newSecret != null,
        accountId = accountId,
      )
      val settings = ModelSettings(
        providerId = provider.id,
        providerName = provider.name,
        endpointType = endpoint.value,
        baseUrl = baseUrl,
        modelName = modelName,
        secretId = secretId,
        apiKey = newSecret,
      )
      resultMessage = null
      errorMessage = null
      settingsGate.launch {
        try {
          val savedSecret = withContext(Dispatchers.IO) {
            persistModelSettings(settings, secretStore, runtimeClient::saveModelConfig)
          }
          currentSecretId = secretId
          hasSavedSecret = savedSecret
          if (
            pendingApiKey == capturedPendingApiKey &&
            pendingApiKeyProviderId == capturedPendingProviderId
          ) {
            pendingApiKey = ""
            pendingApiKeyProviderId = null
          }
          dialogApiKey = ""
          secretDialogProviderId = null
          resultMessage = strings.text("android.settings.settingsSaved")
          onSaved()
        } catch (cancelled: CancellationException) {
          throw cancelled
        } catch (error: Exception) {
          errorMessage = error.message ?: "Unable to save settings"
        } finally {
          settingsGate.finish()
        }
      }
    }
  }

  BackHandler {
    if (!saving) onBack()
  }

  Column(modifier = Modifier.fillMaxSize().background(GaSurface)) {
    SettingsTopBar(onBack, enabled = !saving)
    Column(
      modifier = Modifier
        .weight(1f)
        .widthIn(max = 720.dp)
        .fillMaxWidth()
        .align(Alignment.CenterHorizontally)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 16.dp, vertical = 16.dp),
      verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
          strings.text("appearance.title"),
          color = GaText,
          fontSize = 15.sp,
          lineHeight = 18.sp,
          fontWeight = FontWeight.Medium,
        )
        Text(
          strings.text("android.settings.appearanceDescription"),
          color = GaTextSecondary,
          fontSize = 14.sp,
          lineHeight = 20.sp,
        )
      }
      LabeledOptionField(
        label = strings.text("appearance.colorTheme"),
        value = appearance.themes.firstOrNull { it.id == selectedThemeId }?.label
          ?: appearance.themes.first().label,
        options = appearance.themes,
        optionLabel = AgentAppTheme::label,
        enabled = true,
        onSelect = { onThemeSelected(it.id) },
      )
      LabeledOptionField(
        label = strings.text("language.displayLanguage"),
        value = localization.locales.firstOrNull { it.id == selectedLocaleId }?.label
          ?: localization.locales.first().label,
        options = localization.locales,
        optionLabel = AgentAppLocale::label,
        enabled = true,
        onSelect = { onLocaleSelected(it.id) },
      )
      HorizontalDivider(color = GaBorder)

      identityStatus?.let { status ->
        AccountSettingsCard(
          accountId = checkNotNull(status.accountId),
          expiresAt = checkNotNull(status.securityContext).expiresAt,
          onSwitchAccount = onSwitchAccount,
          onSignOut = onSignOut,
          onClearAccountData = onClearAccountData,
        )
        HorizontalDivider(color = GaBorder)
      }

      if (userConfigurable) {
      Text(
        strings.text("android.settings.model"),
        color = GaText,
        fontSize = 15.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Medium,
      )
      LabeledOptionField(
        label = strings.text("android.settings.provider"),
        value = provider.label,
        options = ProviderOptions,
        optionLabel = { it.label },
        enabled = settingsInteractionAllowed(),
        onSelect = { selected ->
          if (
            settingsInteractionAllowed() &&
            providerSelectionChanges(provider.id, selected.id)
          ) {
            val previous = provider
            provider = selected
            currentSecretId = null
            hasSavedSecret = false
            secretLookupReady = false
            pendingApiKey = ""
            pendingApiKeyProviderId = null
            dialogApiKey = ""
            secretDialogProviderId = null
            if (baseUrl == previous.defaultBaseUrl) baseUrl = selected.defaultBaseUrl
            if (modelName == previous.defaultModel) modelName = selected.defaultModel
          }
        },
      )
      LabeledOptionField(
        label = strings.text("android.settings.endpointType"),
        value = endpoint.label,
        options = EndpointOptions,
        optionLabel = { it.label },
        enabled = settingsInteractionAllowed(),
        onSelect = {
          if (settingsInteractionAllowed()) endpoint = it
        },
      )
      LabeledTextField(
        label = strings.text("android.settings.baseUrl"),
        value = baseUrl,
        enabled = settingsInteractionAllowed(),
        onValueChange = {
          if (settingsInteractionAllowed()) baseUrl = it
        },
      )
      LabeledTextField(
        label = strings.text("android.settings.model"),
        value = modelName,
        enabled = settingsInteractionAllowed(),
        onValueChange = {
          if (settingsInteractionAllowed()) modelName = it
        },
      )

      HorizontalDivider(color = GaBorder)
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
          strings.text("android.settings.apiAuthentication"),
          color = GaText,
          fontSize = 15.sp,
          lineHeight = 18.sp,
          fontWeight = FontWeight.Medium,
        )
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .background(GaSurfaceMuted, GaLargeShape)
            .border(1.dp, GaBorder, GaLargeShape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Icon(
            Icons.Outlined.Lock,
            contentDescription = null,
            tint = GaTextSecondary,
            modifier = Modifier.size(20.dp),
          )
          Spacer(modifier = Modifier.size(12.dp))
          Text(
            text = if (hasSavedSecret) strings.text("android.settings.keySaved") else strings.text("android.settings.keyNotSaved"),
            color = GaTextSecondary,
            fontSize = 14.sp,
            modifier = Modifier.weight(1f),
          )
          Spacer(modifier = Modifier.size(8.dp))
          OutlinedButton(
            onClick = {
              if (settingsInteractionAllowed()) {
                dialogApiKey = ""
                secretDialogProviderId = provider.id
                showSecretDialog = true
              }
            },
            enabled = settingsInteractionAllowed(),
            modifier = Modifier.widthIn(min = 96.dp).height(48.dp),
            shape = GaLargeShape,
          ) {
            Text(if (hasSavedSecret) strings.text("android.settings.replace") else strings.text("android.settings.add"))
          }
        }
        Text(
          strings.text("android.settings.secretReferenceHint"),
          color = GaTextSecondary,
          fontSize = 14.sp,
          lineHeight = 20.sp,
        )
      }

      Button(
        onClick = saveSettings,
        enabled = canSaveModelSettings(
          saving = saving,
          initialConfigReady = initialConfigReady,
          secretLookupReady = secretLookupReady,
          hasReplacementSecret = hasReplacementSecret,
          runtimeBusy = runtimeBusy,
        ),
        modifier = Modifier.padding(top = 24.dp).fillMaxWidth().height(48.dp),
        shape = GaLargeShape,
        colors = ButtonDefaults.buttonColors(containerColor = GaPrimaryActive),
      ) {
        Text(
          if (saving) strings.text("android.settings.saving") else strings.text("android.settings.save"),
          fontSize = 16.sp,
          fontWeight = FontWeight.SemiBold,
        )
      }
      resultMessage?.let { Text(it, color = GaReady, fontSize = 13.sp) }
      errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
      } else {
        ManagedModelConfigurationCard(
          providerName = provider.name,
          modelName = modelName,
        )
        errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
      }
    }
  }

  if (userConfigurable && showSecretDialog) {
    AlertDialog(
      onDismissRequest = {
        dialogApiKey = ""
        secretDialogProviderId = null
        showSecretDialog = false
      },
      shape = GaLargeShape,
      title = { Text(strings.text("android.settings.apiKey")) },
      text = {
        BasicTextField(
          value = dialogApiKey,
          onValueChange = {
            dialogApiKey = it
          },
          singleLine = true,
          visualTransformation = PasswordVisualTransformation(),
          textStyle = TextStyle(color = GaText, fontSize = 16.sp),
          modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .border(1.dp, GaBorder, GaLargeShape)
            .padding(horizontal = 12.dp, vertical = 14.dp),
        )
      },
      confirmButton = {
        Button(
          onClick = {
            pendingApiKey = dialogApiKey
            pendingApiKeyProviderId = secretDialogProviderId
            dialogApiKey = ""
            secretDialogProviderId = null
            showSecretDialog = false
          },
          enabled = dialogApiKey.isNotBlank(),
          shape = GaLargeShape,
        ) {
          Text(strings.text("android.settings.useKey"))
        }
      },
      dismissButton = {
        OutlinedButton(
          onClick = {
            dialogApiKey = ""
            secretDialogProviderId = null
            showSecretDialog = false
          },
          shape = GaLargeShape,
        ) {
          Text(strings.text("common.cancel"))
        }
      },
    )
  }
}

@Composable
private fun ManagedModelConfigurationCard(providerName: String, modelName: String) {
  val strings = LocalAppStrings.current
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(
      strings.text("android.settings.model"),
      color = GaText,
      fontSize = 15.sp,
      lineHeight = 18.sp,
      fontWeight = FontWeight.Medium,
    )
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .background(GaSurfaceMuted, GaLargeShape)
        .border(1.dp, GaBorder, GaLargeShape)
        .padding(16.dp),
      horizontalArrangement = Arrangement.spacedBy(12.dp),
      verticalAlignment = Alignment.Top,
    ) {
      Icon(
        Icons.Outlined.Lock,
        contentDescription = null,
        tint = GaReady,
        modifier = Modifier.size(20.dp),
      )
      Column(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(6.dp),
      ) {
        Text(
          strings.text("android.settings.modelManagedTitle"),
          color = GaText,
          fontSize = 15.sp,
          lineHeight = 20.sp,
          fontWeight = FontWeight.SemiBold,
        )
        Text(
          strings.text("android.settings.modelManagedDescription"),
          color = GaTextSecondary,
          fontSize = 14.sp,
          lineHeight = 20.sp,
        )
        Text(
          "$providerName · $modelName",
          color = GaTextSecondary,
          fontFamily = LocalGaMonoFontFamily.current,
          fontSize = 13.sp,
          lineHeight = 18.sp,
        )
      }
    }
  }
}

@Composable
private fun SettingsTopBar(onBack: () -> Unit, enabled: Boolean) {
  val strings = LocalAppStrings.current
  Row(
    modifier = Modifier.fillMaxWidth().height(56.dp).background(GaSurface),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    IconButton(onClick = onBack, enabled = enabled, modifier = Modifier.size(48.dp)) {
      Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = strings.text("common.backToChat"), tint = GaText)
    }
    Text(
      strings.text("settings.title"),
      style = MaterialTheme.typography.headlineSmall,
      color = GaText,
      modifier = Modifier.weight(1f).padding(start = 16.dp),
    )
    Spacer(modifier = Modifier.size(48.dp))
  }
  HorizontalDivider(color = GaBorder)
}

@Composable
private fun LabeledTextField(
  label: String,
  value: String,
  enabled: Boolean,
  onValueChange: (String) -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(
      label,
      color = GaText,
      fontSize = 15.sp,
      lineHeight = 18.sp,
      fontWeight = FontWeight.Medium,
    )
    BasicTextField(
      value = value,
      onValueChange = onValueChange,
      enabled = enabled,
      singleLine = true,
      textStyle = TextStyle(
        color = GaText,
        fontFamily = LocalGaMonoFontFamily.current,
        fontSize = 17.sp,
        lineHeight = 24.sp,
      ),
      modifier = Modifier
        .fillMaxWidth()
        .height(48.dp)
        .background(GaSurface, GaLargeShape)
        .border(1.dp, GaBorder, GaLargeShape)
        .padding(horizontal = 12.dp, vertical = 13.dp),
    )
  }
}

@Composable
private fun <T> LabeledOptionField(
  label: String,
  value: String,
  options: List<T>,
  optionLabel: (T) -> String,
  enabled: Boolean,
  onSelect: (T) -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(
      label,
      color = GaText,
      fontSize = 15.sp,
      lineHeight = 18.sp,
      fontWeight = FontWeight.Medium,
    )
    Box {
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .height(48.dp)
          .background(GaSurface, GaLargeShape)
          .border(1.dp, GaBorder, GaLargeShape)
          .clickable(enabled = enabled) { expanded = true }
          .semantics(mergeDescendants = true) {
            role = Role.Button
            stateDescription = value
          }
          .padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(value, color = GaText, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Box(modifier = Modifier.size(48.dp), contentAlignment = Alignment.Center) {
          Icon(
            Icons.Outlined.KeyboardArrowDown,
            contentDescription = "Open $label",
            tint = GaTextSecondary,
            modifier = Modifier.size(24.dp),
          )
        }
      }
      DropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false },
        modifier = Modifier.background(GaSurface),
      ) {
        options.forEach { option ->
          DropdownMenuItem(
            text = { Text(optionLabel(option)) },
            onClick = {
              onSelect(option)
              expanded = false
            },
          )
        }
      }
    }
  }
}

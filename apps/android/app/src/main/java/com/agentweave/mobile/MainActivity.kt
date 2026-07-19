package com.agentweave.mobile

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModelProvider
import com.agentweave.mobile.runtime.AndroidAgentAppAppearanceStore
import com.agentweave.mobile.runtime.AndroidAgentAppLocalizationStore
import com.agentweave.mobile.ui.AgentWeaveTheme
import com.agentweave.mobile.ui.AppRoot
import com.agentweave.mobile.ui.IdentityFailureScreen
import com.agentweave.mobile.ui.IdentityLoadingScreen
import com.agentweave.mobile.ui.IdentityRequiredScreen
import com.agentweave.mobile.ui.LocalAppStrings

class MainActivity : ComponentActivity() {
  private val requestNotifications =
    registerForActivityResult(ActivityResultContracts.RequestPermission()) { }
  private lateinit var runtimeViewModel: RuntimeHostViewModel

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    runtimeViewModel = ViewModelProvider(
      this,
      RuntimeHostViewModel.factory(this),
    )[RuntimeHostViewModel::class.java]
    consumeIdentityCallback(intent)

    val appearanceStore = AndroidAgentAppAppearanceStore(this)
    val appearance = appearanceStore.appearance
    val localizationStore = AndroidAgentAppLocalizationStore(this)
    val localization = localizationStore.localization
    setContent {
      val hostState by runtimeViewModel.state.collectAsState()
      var selectedThemeId by remember { mutableStateOf(appearanceStore.selectedTheme()) }
      var selectedLocaleId by remember { mutableStateOf(localizationStore.selectedLocale()) }

      LaunchedEffect(runtimeViewModel) {
        runtimeViewModel.browserEvents.collect { url ->
          runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
          }.onFailure {
            runtimeViewModel.onBrowserLaunchFailed()
          }
        }
      }

      CompositionLocalProvider(LocalAppStrings provides localization.strings(selectedLocaleId)) {
        AgentWeaveTheme(appearance, selectedThemeId) {
          val selectedTheme = appearance.themes.firstOrNull { it.id == selectedThemeId }
          val lightTheme = selectedTheme?.type == "light" || selectedTheme?.type == "hcLight"
          SideEffect {
            val style = if (lightTheme) {
              SystemBarStyle.light(
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
              )
            } else {
              SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
            }
            enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
          }

          val modifier = Modifier
            .background(MaterialTheme.colorScheme.background)
            .safeDrawingPadding()
          when (val state = hostState) {
            RuntimeHostState.Loading -> IdentityLoadingScreen(modifier)
            is RuntimeHostState.AuthenticationRequired -> IdentityRequiredScreen(
              appDisplayName = state.appDisplayName,
              phase = state.phase,
              errorMessage = state.errorMessage,
              onSignIn = runtimeViewModel::beginSignIn,
              modifier = modifier,
            )
            is RuntimeHostState.Failed -> IdentityFailureScreen(
              appDisplayName = state.appDisplayName,
              message = state.message,
              onRetry = runtimeViewModel::retryInitialization,
              modifier = modifier,
            )
            is RuntimeHostState.Ready -> {
              val session = state.session
              AppRoot(
                runtimeClient = session.client,
                turnGate = session.turnGate,
                settingsGate = session.settingsGate,
                initialDiagnostics = session.diagnostics,
                secretStore = session.secretStore,
                identityStatus = session.identityStatus,
                onSwitchAccount = runtimeViewModel::beginSignIn,
                onSignOut = runtimeViewModel::signOut,
                onClearAccountData = runtimeViewModel::clearAccountData,
                appearance = appearance,
                selectedThemeId = selectedThemeId,
                localization = localization,
                selectedLocaleId = selectedLocaleId,
                onThemeSelected = { themeId ->
                  appearanceStore.selectTheme(themeId)
                  selectedThemeId = appearance.admittedTheme(themeId)
                },
                onLocaleSelected = { localeId ->
                  localizationStore.selectLocale(localeId)
                  selectedLocaleId = localization.admittedLocale(localeId)
                },
                modifier = modifier,
              )
            }
          }
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    consumeIdentityCallback(intent)
  }

  override fun onResume() {
    super.onResume()
    if (::runtimeViewModel.isInitialized) runtimeViewModel.onHostResume()
  }

  private fun consumeIdentityCallback(intent: Intent?) {
    intent?.dataString?.let(runtimeViewModel::handleIdentityCallback)
    intent?.data = null
  }
}

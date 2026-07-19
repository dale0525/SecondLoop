package com.agentweave.mobile

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.CreationExtras
import com.agentweave.mobile.runtime.MobileIdentityBridge
import com.agentweave.mobile.runtime.MobileIdentityBridgeException
import com.agentweave.mobile.runtime.MobileIdentityClient
import com.agentweave.mobile.runtime.MobileIdentitySessionState
import com.agentweave.mobile.runtime.MobileIdentityStatus
import com.agentweave.mobile.runtime.RuntimeAccountCoordinator
import com.agentweave.mobile.runtime.RuntimeAccountDataStore
import com.agentweave.mobile.runtime.AndroidRuntimeAccountDataStore
import com.agentweave.mobile.runtime.RuntimeBridge
import com.agentweave.mobile.runtime.RuntimeClient
import com.agentweave.mobile.runtime.RuntimeDiagnostics
import com.agentweave.mobile.runtime.RuntimeGatewayCredentialProvider
import com.agentweave.mobile.secrets.AndroidKeystoreModelSecretStore
import com.agentweave.mobile.secrets.InMemoryModelSecretStore
import com.agentweave.mobile.secrets.ModelSecretStore
import com.agentweave.mobile.ui.RuntimeSettingsGate
import com.agentweave.mobile.ui.RuntimeTurnGate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.security.MessageDigest

enum class IdentityPromptPhase {
  SignedOut,
  WaitingForBrowser,
  Completing,
  Expired,
  Unavailable,
}

sealed interface RuntimeHostState {
  data object Loading : RuntimeHostState

  data class AuthenticationRequired(
    val appDisplayName: String,
    val phase: IdentityPromptPhase,
    val errorMessage: String? = null,
    val expiresAt: String? = null,
  ) : RuntimeHostState

  data class Ready(val session: RuntimeUiSession) : RuntimeHostState

  data class Failed(
    val appDisplayName: String,
    val message: String,
  ) : RuntimeHostState
}

data class RuntimeUiSession(
  val client: RuntimeClient,
  val diagnostics: RuntimeDiagnostics,
  val secretStore: ModelSecretStore,
  val turnGate: RuntimeTurnGate,
  val settingsGate: RuntimeSettingsGate,
  val identityStatus: MobileIdentityStatus?,
)

internal class RuntimeHostViewModel(
  private val appContext: Context,
) : ViewModel() {
  private val mutableState = MutableStateFlow<RuntimeHostState>(RuntimeHostState.Loading)
  private val browserChannel = Channel<String>(Channel.BUFFERED)
  private val identityMutation = Mutex()
  private var identity: MobileIdentityClient? = null
  private var coordinator: RuntimeAccountCoordinator? = null
  private var activeSession: RuntimeUiSession? = null
  private var legacyClient: RuntimeClient? = null
  private var pendingCallback: String? = null
  private val callbackDigests = linkedSetOf<String>()

  val state: StateFlow<RuntimeHostState> = mutableState.asStateFlow()
  val browserEvents = browserChannel.receiveAsFlow()

  init {
    if (RuntimeDependencies.hasLegacyRuntimeOverride()) {
      initializeLegacyRuntime()
    } else {
      viewModelScope.launch { initializeIdentityRuntime() }
    }
  }

  fun beginSignIn() {
    viewModelScope.launch {
      identityMutation.withLock {
        val client = identity ?: return@withLock
        val current = mutableState.value
        val switchingAccount = current is RuntimeHostState.Ready
        val appName = current.appDisplayName()
        closeActiveGates()
        mutableState.value = RuntimeHostState.AuthenticationRequired(
          appDisplayName = appName,
          phase = IdentityPromptPhase.Completing,
        )
        try {
          val start = withContext(Dispatchers.IO) {
            client.beginAuthorization(forceAccountSelection = switchingAccount)
          }
          browserChannel.send(safeBrowserUrl(start.authorizationUrl))
          mutableState.value = RuntimeHostState.AuthenticationRequired(
            appDisplayName = appName,
            phase = IdentityPromptPhase.WaitingForBrowser,
            expiresAt = start.expiresAt,
          )
        } catch (cancelled: CancellationException) {
          throw cancelled
        } catch (error: Exception) {
          mutableState.value = RuntimeHostState.AuthenticationRequired(
            appDisplayName = appName,
            phase = IdentityPromptPhase.Unavailable,
            errorMessage = error.safeIdentityMessage(),
          )
        }
      }
    }
  }

  fun retryInitialization() {
    if (identity != null || mutableState.value !is RuntimeHostState.Failed) return
    mutableState.value = RuntimeHostState.Loading
    viewModelScope.launch { initializeIdentityRuntime() }
  }

  fun handleIdentityCallback(callbackUrl: String) {
    if (callbackUrl.length > MAX_CALLBACK_URL_BYTES) return
    val digest = MessageDigest.getInstance("SHA-256")
      .digest(callbackUrl.toByteArray(Charsets.UTF_8))
      .joinToString("") { byte -> "%02x".format(byte) }
    synchronized(callbackDigests) {
      if (!callbackDigests.add(digest)) return
      while (callbackDigests.size > MAX_CALLBACK_DIGESTS) {
        callbackDigests.remove(callbackDigests.first())
      }
    }
    if (identity == null) {
      pendingCallback = callbackUrl
      return
    }
    viewModelScope.launch { completeIdentityCallback(callbackUrl) }
  }

  fun signOut() {
    viewModelScope.launch {
      identityMutation.withLock {
        val client = identity ?: return@withLock
        val appName = mutableState.value.appDisplayName()
        mutableState.value = RuntimeHostState.AuthenticationRequired(
          appDisplayName = appName,
          phase = IdentityPromptPhase.Completing,
        )
        withContext(Dispatchers.IO) { coordinator?.close() }
        activeSession = null
        try {
          val outcome = withContext(Dispatchers.IO) { client.logout() }
          outcome.endSessionUrl?.let { browserChannel.send(safeBrowserUrl(it)) }
          mutableState.value = promptFor(outcome.status)
        } catch (cancelled: CancellationException) {
          throw cancelled
        } catch (error: Exception) {
          mutableState.value = RuntimeHostState.AuthenticationRequired(
            appDisplayName = appName,
            phase = IdentityPromptPhase.Unavailable,
            errorMessage = error.safeIdentityMessage(),
          )
        }
      }
    }
  }

  fun clearAccountData() {
    viewModelScope.launch {
      identityMutation.withLock {
        val client = identity ?: return@withLock
        val ready = mutableState.value as? RuntimeHostState.Ready ?: return@withLock
        val accountId = ready.session.identityStatus?.accountId ?: return@withLock
        val appName = ready.session.diagnostics.appDisplayName
        mutableState.value = RuntimeHostState.AuthenticationRequired(
          appDisplayName = appName,
          phase = IdentityPromptPhase.Completing,
        )
        withContext(Dispatchers.IO) { coordinator?.close() }
        activeSession = null
        try {
          val outcome = withContext(Dispatchers.IO) { client.logout() }
          withContext(Dispatchers.IO) {
            RuntimeDependencies.accountDataStoreFactory(appContext).clear(accountId)
          }
          outcome.endSessionUrl?.let { browserChannel.send(safeBrowserUrl(it)) }
          mutableState.value = promptFor(outcome.status)
        } catch (cancelled: CancellationException) {
          throw cancelled
        } catch (error: Exception) {
          mutableState.value = RuntimeHostState.AuthenticationRequired(
            appDisplayName = appName,
            phase = IdentityPromptPhase.Unavailable,
            errorMessage = error.safeIdentityMessage(),
          )
        }
      }
    }
  }

  fun onBrowserLaunchFailed() {
    val current = mutableState.value as? RuntimeHostState.AuthenticationRequired ?: return
    mutableState.value = current.copy(
      phase = IdentityPromptPhase.Unavailable,
      errorMessage = "Unable to open the secure sign-in browser",
    )
  }

  fun onHostResume() {
    val current = mutableState.value as? RuntimeHostState.Ready ?: return
    val client = identity ?: return
    viewModelScope.launch {
      val status = withContext(Dispatchers.IO) { client.status() }
      when (status.state) {
        MobileIdentitySessionState.SignedIn -> {
          if (status.accountId == current.session.identityStatus?.accountId) {
            status.securityContext?.let { context ->
              withContext(Dispatchers.IO) { current.session.client.refreshSecurityContext(context) }
            }
            val updated = current.session.copy(identityStatus = status)
            activeSession = updated
            mutableState.value = RuntimeHostState.Ready(updated)
          } else {
            expireSession(status)
          }
        }
        MobileIdentitySessionState.Expired,
        MobileIdentitySessionState.SignedOut,
        MobileIdentitySessionState.Unavailable,
        -> expireSession(status)
        MobileIdentitySessionState.NotRequired -> Unit
      }
    }
  }

  override fun onCleared() {
    runCatching { coordinator?.close() }
    closeActiveGates()
    runCatching { legacyClient?.close() }
    runCatching { identity?.close() }
    browserChannel.close()
  }

  private fun initializeLegacyRuntime() {
    try {
      val client = RuntimeDependencies.runtimeLoader(appContext)
      legacyClient = client
      val session = RuntimeUiSession(
        client = client,
        diagnostics = client.diagnostics(),
        secretStore = InMemoryModelSecretStore(),
        turnGate = RuntimeTurnGate(),
        settingsGate = RuntimeSettingsGate(),
        identityStatus = null,
      )
      activeSession = session
      mutableState.value = RuntimeHostState.Ready(session)
    } catch (error: Exception) {
      mutableState.value = RuntimeHostState.Failed(
        appDisplayName = "AgentWeave",
        message = error.message ?: "Runtime could not be initialized",
      )
    }
  }

  private suspend fun initializeIdentityRuntime() {
    try {
      val loadedIdentity = withContext(Dispatchers.IO) {
        RuntimeDependencies.identityLoader(appContext)
      }
      identity = loadedIdentity
      coordinator = RuntimeAccountCoordinator(
        bridge = RuntimeDependencies.runtimeBridgeFactory(appContext),
        secretStoreForAccount = { accountId ->
          RuntimeDependencies.modelSecretStoreFactory(appContext, accountId)
        },
        stopActiveWork = ::closeActiveGates,
      )
      val status = withContext(Dispatchers.IO) { loadedIdentity.status() }
      applyIdentityStatus(status)
      pendingCallback?.also { pendingCallback = null }?.let { callback ->
        completeIdentityCallback(callback)
      }
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      mutableState.value = RuntimeHostState.Failed(
        appDisplayName = "AgentWeave",
        message = error.safeIdentityMessage(),
      )
    }
  }

  private suspend fun completeIdentityCallback(callbackUrl: String) {
    identityMutation.withLock {
      val client = identity ?: return@withLock
      val appName = mutableState.value.appDisplayName()
      mutableState.value = RuntimeHostState.AuthenticationRequired(
        appDisplayName = appName,
        phase = IdentityPromptPhase.Completing,
      )
      withContext(Dispatchers.IO) { coordinator?.close() }
      activeSession = null
      try {
        val status = withContext(Dispatchers.IO) {
          client.completeAuthorization(callbackUrl)
        }
        applyIdentityStatus(status)
      } catch (cancelled: CancellationException) {
        throw cancelled
      } catch (error: Exception) {
        mutableState.value = RuntimeHostState.AuthenticationRequired(
          appDisplayName = appName,
          phase = if (error is MobileIdentityBridgeException && error.authenticationRequired) {
            IdentityPromptPhase.SignedOut
          } else {
            IdentityPromptPhase.Unavailable
          },
          errorMessage = error.safeIdentityMessage(),
        )
      }
    }
  }

  private suspend fun applyIdentityStatus(status: MobileIdentityStatus) {
    when (status.state) {
      MobileIdentitySessionState.NotRequired -> activateRuntime(status, null)
      MobileIdentitySessionState.SignedIn -> {
        val context = checkNotNull(status.securityContext) {
          "Signed-in identity is missing its security context"
        }
        activateRuntime(status, context)
      }
      MobileIdentitySessionState.SignedOut,
      MobileIdentitySessionState.Expired,
      MobileIdentitySessionState.Unavailable,
      -> mutableState.value = promptFor(status)
    }
  }

  private suspend fun activateRuntime(
    status: MobileIdentityStatus,
    context: com.agentweave.mobile.runtime.RuntimeSecurityContext?,
  ) {
    val gatewayProvider = context?.let {
      RuntimeGatewayCredentialProvider {
        try {
          checkNotNull(identity).gatewayCredential()
        } catch (error: MobileIdentityBridgeException) {
          if (error.authenticationRequired) {
            viewModelScope.launch { expireSession(checkNotNull(identity).status()) }
          }
          throw error
        }
      }
    }
    val account = withContext(Dispatchers.IO) {
      checkNotNull(coordinator).start(context, gatewayProvider)
    }
    val session = RuntimeUiSession(
      client = account.client,
      diagnostics = account.diagnostics,
      secretStore = account.secretStore,
      turnGate = RuntimeTurnGate(),
      settingsGate = RuntimeSettingsGate(),
      identityStatus = status.takeUnless {
        it.state == MobileIdentitySessionState.NotRequired
      },
    )
    activeSession = session
    mutableState.value = RuntimeHostState.Ready(session)
  }

  private suspend fun expireSession(status: MobileIdentityStatus) {
    withContext(Dispatchers.IO) { coordinator?.close() }
    activeSession = null
    mutableState.value = promptFor(status)
  }

  private fun promptFor(status: MobileIdentityStatus): RuntimeHostState.AuthenticationRequired =
    RuntimeHostState.AuthenticationRequired(
      appDisplayName = status.appDisplayName,
      phase = when (status.state) {
        MobileIdentitySessionState.Expired -> IdentityPromptPhase.Expired
        MobileIdentitySessionState.Unavailable -> IdentityPromptPhase.Unavailable
        else -> IdentityPromptPhase.SignedOut
      },
    )

  private fun closeActiveGates() {
    activeSession?.turnGate?.close()
    activeSession?.settingsGate?.close()
  }

  companion object {
    fun factory(context: Context): ViewModelProvider.Factory =
      object : ViewModelProvider.Factory {
        override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
          require(modelClass == RuntimeHostViewModel::class.java) {
            "unsupported ViewModel: ${modelClass.name}"
          }
          @Suppress("UNCHECKED_CAST")
          return RuntimeHostViewModel(context.applicationContext) as T
        }
      }
  }
}

internal object RuntimeDependencies {
  private val defaultRuntimeLoader: (Context) -> RuntimeClient = { context ->
    RuntimeBridge(context).load()
  }
  private var legacyRuntimeOverride = false

  var runtimeLoader: (Context) -> RuntimeClient = defaultRuntimeLoader
    set(value) {
      field = value
      legacyRuntimeOverride = true
    }

  var identityLoader: (Context) -> MobileIdentityClient = MobileIdentityBridge::load
  var runtimeBridgeFactory: (Context) -> RuntimeBridge = ::RuntimeBridge
  var modelSecretStoreFactory: (Context, String?) -> ModelSecretStore = { context, accountId ->
    AndroidKeystoreModelSecretStore(context, accountId)
  }
  var accountDataStoreFactory: (Context) -> RuntimeAccountDataStore = ::AndroidRuntimeAccountDataStore

  fun hasLegacyRuntimeOverride(): Boolean = legacyRuntimeOverride

  fun reset() {
    runtimeLoader = defaultRuntimeLoader
    legacyRuntimeOverride = false
    identityLoader = MobileIdentityBridge::load
    runtimeBridgeFactory = ::RuntimeBridge
    modelSecretStoreFactory = { context, accountId ->
      AndroidKeystoreModelSecretStore(context, accountId)
    }
    accountDataStoreFactory = ::AndroidRuntimeAccountDataStore
  }
}

private fun RuntimeHostState.appDisplayName(): String = when (this) {
  RuntimeHostState.Loading -> "AgentWeave"
  is RuntimeHostState.AuthenticationRequired -> appDisplayName
  is RuntimeHostState.Ready -> session.diagnostics.appDisplayName
  is RuntimeHostState.Failed -> appDisplayName
}

private fun safeBrowserUrl(value: String): String {
  require(value.length in 1..MAX_BROWSER_URL_BYTES) { "Identity browser URL is invalid" }
  val uri = Uri.parse(value)
  val loopback = uri.scheme == "http" && (uri.host == "127.0.0.1" || uri.host == "localhost")
  require((uri.scheme == "https" || loopback) && uri.userInfo == null && uri.fragment == null) {
    "Identity browser URL is invalid"
  }
  return uri.toString()
}

private fun Exception.safeIdentityMessage(): String = when (this) {
  is MobileIdentityBridgeException -> message ?: "Identity operation failed"
  else -> message ?: "Identity operation failed"
}

private const val MAX_CALLBACK_URL_BYTES = 16 * 1024
private const val MAX_BROWSER_URL_BYTES = 16 * 1024
private const val MAX_CALLBACK_DIGESTS = 16

package com.agentweave.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.SmartToy
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.agentweave.mobile.runtime.RuntimeClient
import com.agentweave.mobile.runtime.RuntimeDiagnostics
import com.agentweave.mobile.runtime.RuntimeGatewayCredentialProvider
import com.agentweave.mobile.runtime.RuntimeMessage
import com.agentweave.mobile.runtime.RuntimeModelConfig
import com.agentweave.mobile.secrets.ModelSecretStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private data class ChatSnapshot(
  val sessionId: String,
  val messages: List<RuntimeMessage>,
)

private data class ChatSendResult(
  val messages: List<RuntimeMessage>?,
  val turnError: Exception?,
  val refreshError: Exception?,
  val userPersisted: Boolean,
)

data class ResolvedTurnCredential(
  val bearerToken: String?,
  val securityContext: com.agentweave.mobile.runtime.RuntimeSecurityContext? = null,
)

class RuntimeTurnGate {
  private var active = false
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val mutableInFlight = MutableStateFlow(false)
  private val mutableCompletionVersion = MutableStateFlow(0)
  private val mutableDraft = MutableStateFlow("")
  private val mutablePendingUserMessage = MutableStateFlow<RuntimeMessage?>(null)
  private val mutablePendingExistingMessageIds = MutableStateFlow<Set<String>>(emptySet())
  private val mutableTurnErrorMessage = MutableStateFlow<String?>(null)

  val inFlight: StateFlow<Boolean> = mutableInFlight.asStateFlow()
  val completionVersion: StateFlow<Int> = mutableCompletionVersion.asStateFlow()
  val draft: StateFlow<String> = mutableDraft.asStateFlow()
  val pendingUserMessage: StateFlow<RuntimeMessage?> = mutablePendingUserMessage.asStateFlow()
  val pendingExistingMessageIds: StateFlow<Set<String>> = mutablePendingExistingMessageIds.asStateFlow()
  val turnErrorMessage: StateFlow<String?> = mutableTurnErrorMessage.asStateFlow()

  @Synchronized
  fun tryBegin(
    pendingUserMessage: RuntimeMessage? = null,
    existingMessageIds: Set<String> = emptySet(),
  ): Boolean {
    if (active) return false
    active = true
    mutablePendingUserMessage.value = pendingUserMessage
    mutablePendingExistingMessageIds.value = existingMessageIds
    mutableTurnErrorMessage.value = null
    mutableInFlight.value = true
    return true
  }

  @Synchronized
  fun finish(refreshHistory: Boolean = false) {
    if (refreshHistory) {
      mutableCompletionVersion.value += 1
    }
    mutablePendingUserMessage.value = null
    mutablePendingExistingMessageIds.value = emptySet()
    mutableInFlight.value = false
    active = false
  }

  fun reportTurnError(message: String) {
    mutableTurnErrorMessage.value = message
  }

  fun updateDraft(value: String) {
    mutableDraft.value = value
  }

  fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)

  fun close() {
    scope.cancel()
  }
}

fun chatMessagesForDisplay(
  messages: List<RuntimeMessage>,
  pendingUserMessage: RuntimeMessage?,
  existingMessageIds: Set<String>,
): List<RuntimeMessage> {
  if (pendingUserMessage == null) return messages
  val pendingPersisted = messages.any { message ->
    message.id !in existingMessageIds &&
      message.sessionId == pendingUserMessage.sessionId &&
      message.role == pendingUserMessage.role &&
      message.content == pendingUserMessage.content
  }
  return if (pendingPersisted) messages else messages + pendingUserMessage
}

fun resolveTurnCredential(
  modelConfigurationPolicy: String,
  modelConfig: RuntimeModelConfig?,
  secretStore: ModelSecretStore,
  gatewayCredentialProvider: RuntimeGatewayCredentialProvider?,
): ResolvedTurnCredential = when (modelConfigurationPolicy) {
  "user_configurable" -> ResolvedTurnCredential(
    modelConfig?.secretId?.let(secretStore::loadSecret),
  )
  "app_managed" -> gatewayCredentialProvider?.credential()?.let { credential ->
    ResolvedTurnCredential(
      bearerToken = credential.bearerToken.trim().takeIf(String::isNotEmpty),
      securityContext = credential.securityContext,
    )
  } ?: ResolvedTurnCredential(null)
  else -> throw IllegalStateException("Unsupported model configuration policy")
}

class RuntimeSettingsGate {
  private var active = false
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val mutableInFlight = MutableStateFlow(false)
  private val mutableCompletionVersion = MutableStateFlow(0)

  val inFlight: StateFlow<Boolean> = mutableInFlight.asStateFlow()
  val completionVersion: StateFlow<Int> = mutableCompletionVersion.asStateFlow()

  @Synchronized
  fun tryBegin(): Boolean {
    if (active) return false
    active = true
    mutableInFlight.value = true
    return true
  }

  @Synchronized
  fun finish() {
    mutableCompletionVersion.value += 1
    mutableInFlight.value = false
    active = false
  }

  fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)

  fun close() {
    scope.cancel()
  }
}

@Composable
fun ChatScreen(
  runtimeClient: RuntimeClient,
  turnGate: RuntimeTurnGate,
  diagnostics: RuntimeDiagnostics,
  secretStore: ModelSecretStore,
  onRefreshDiagnostics: () -> Unit,
  interactionAllowed: () -> Boolean,
  modifier: Modifier = Modifier,
) {
  val strings = LocalAppStrings.current
  var snapshot by remember { mutableStateOf<ChatSnapshot?>(null) }
  var errorMessage by remember { mutableStateOf<String?>(null) }
  var refreshToken by remember { mutableIntStateOf(0) }
  val snapshotLoadMutex = remember { Mutex() }
  val focusManager = LocalFocusManager.current
  val interactionEnabled = interactionAllowed()
  val sending by turnGate.inFlight.collectAsState()
  val completionVersion by turnGate.completionVersion.collectAsState()
  val draft by turnGate.draft.collectAsState()
  val pendingUserMessage by turnGate.pendingUserMessage.collectAsState()
  val pendingExistingMessageIds by turnGate.pendingExistingMessageIds.collectAsState()
  val turnErrorMessage by turnGate.turnErrorMessage.collectAsState()

  LaunchedEffect(interactionEnabled) {
    if (!interactionEnabled) focusManager.clearFocus(force = true)
  }

  LaunchedEffect(runtimeClient, refreshToken, completionVersion) {
    try {
      val loaded = withContext(Dispatchers.IO) {
        snapshotLoadMutex.withLock { runtimeClient.loadChatSnapshot() }
      }
      snapshot = loaded
      errorMessage = null
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      errorMessage = error.message ?: "Unable to load chat history"
    }
  }

  val sendDraft = {
    val content = draft.trim()
    val sessionId = snapshot?.sessionId
    val existingMessageIds = snapshot?.messages.orEmpty().mapTo(mutableSetOf()) { it.id }
    val pendingMessage = sessionId?.let {
      RuntimeMessage(
        id = "pending-user",
        sessionId = it,
        role = "user",
        content = content,
        createdAt = "",
      )
    }
    if (
      content.isNotEmpty() &&
      sessionId != null &&
      pendingMessage != null &&
      !sending &&
      interactionAllowed() &&
      turnGate.tryBegin(pendingMessage, existingMessageIds)
    ) {
      errorMessage = null
      turnGate.launch {
        var sendAttempted = false
        try {
          val credential = withContext(Dispatchers.IO) {
            val config = runtimeClient.loadModelConfig()
            resolveTurnCredential(
              modelConfigurationPolicy = diagnostics.modelConfigurationPolicy,
              modelConfig = config,
              secretStore = secretStore,
              gatewayCredentialProvider = runtimeClient.gatewayCredentialProvider,
            ).also { prepared ->
              prepared.securityContext?.let(runtimeClient::refreshSecurityContext)
            }
          }
          turnGate.updateDraft("")
          sendAttempted = true
          val result = withContext(Dispatchers.IO) {
            var turnError: Exception? = null
            try {
              runtimeClient.sendMessage(sessionId, content, credential.bearerToken)
            } catch (cancelled: CancellationException) {
              throw cancelled
            } catch (error: Exception) {
              turnError = error
            }
            var refreshError: Exception? = null
            val messages = try {
              runtimeClient.getMessages(sessionId)
            } catch (cancelled: CancellationException) {
              throw cancelled
            } catch (error: Exception) {
              refreshError = error
              null
            }
            val userPersisted = messages?.any { message ->
              message.id !in existingMessageIds &&
                message.role == "user" &&
                message.content == content
            } == true
            ChatSendResult(messages, turnError, refreshError, userPersisted)
          }
          result.messages?.let { messages -> snapshot = snapshot?.copy(messages = messages) }
          val failure = result.turnError ?: result.refreshError
          if (failure != null) {
            turnGate.reportTurnError(failure.message ?: if (result.turnError != null) {
              "Model turn failed"
            } else {
              "Unable to refresh chat history"
            })
          }
          if (result.turnError != null && !result.userPersisted && turnGate.draft.value.isEmpty()) {
            turnGate.updateDraft(content)
          }
          onRefreshDiagnostics()
        } catch (cancelled: CancellationException) {
          throw cancelled
        } catch (error: Exception) {
          turnGate.reportTurnError(error.message ?: "Unable to prepare model turn")
        } finally {
          turnGate.finish(refreshHistory = sendAttempted)
        }
      }
    }
  }

  Column(modifier = modifier.fillMaxSize().background(GaSurface)) {
    ChatTopBar(
      ready = diagnostics.databaseReady,
      onRefresh = {
        refreshToken += 1
        onRefreshDiagnostics()
      },
    )
    LazyColumn(
      modifier = Modifier
        .weight(1f)
        .fillMaxWidth()
        .background(GaSurfaceSubtle),
      contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
      verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
      items(
        chatMessagesForDisplay(
          snapshot?.messages.orEmpty(),
          pendingUserMessage,
          pendingExistingMessageIds,
        ),
        key = { it.id },
      ) { message ->
        ChatMessageBubble(message)
      }
      if (sending) {
        item { RunningTurnRow() }
      }
      (turnErrorMessage ?: errorMessage)?.let { message ->
        item { TurnErrorRow(message) }
      }
    }
    ChatComposer(
      draft = draft,
      onDraftChange = turnGate::updateDraft,
      onSend = sendDraft,
      enabled = snapshot != null && !sending && interactionEnabled,
      sending = sending,
      onAttach = { errorMessage = strings.text("android.chat.attachmentsUnavailable") },
    )
  }
}

private fun RuntimeClient.loadChatSnapshot(): ChatSnapshot {
  val session = listSessions().firstOrNull() ?: createSession("Android session")
  return ChatSnapshot(
    sessionId = session.id,
    messages = getMessages(session.id),
  )
}

@Composable
private fun ChatTopBar(ready: Boolean, onRefresh: () -> Unit) {
  val strings = LocalAppStrings.current
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .height(64.dp)
      .background(GaSurface)
      .padding(horizontal = 16.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    IconButton(onClick = {}, modifier = Modifier.size(48.dp)) {
      Icon(Icons.Outlined.SmartToy, contentDescription = strings.text("app.name"), tint = GaPrimary)
    }
    Spacer(modifier = Modifier.size(12.dp))
    Column(modifier = Modifier.weight(1f)) {
      Text(
        text = strings.text("app.name"),
        style = MaterialTheme.typography.titleMedium,
        color = GaText,
      )
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
          text = strings.text("android.chat.runtimeSetup"),
          color = GaTextSecondary,
          fontSize = 12.sp,
          lineHeight = 16.sp,
        )
        Spacer(modifier = Modifier.size(6.dp))
        Box(
          modifier = Modifier
            .widthIn(min = 81.dp)
            .height(20.dp)
            .background(
              if (ready) GaReadyContainer else MaterialTheme.colorScheme.errorContainer,
              GaSmallShape,
            ),
          contentAlignment = Alignment.Center,
        ) {
          Text(
            text = if (ready) strings.text("android.chat.runtimeReady") else strings.text("android.chat.unavailable"),
            color = if (ready) GaReady else MaterialTheme.colorScheme.error,
            fontSize = 10.sp,
            lineHeight = 14.sp,
            fontWeight = FontWeight.Medium,
          )
        }
      }
    }
    IconButton(onClick = onRefresh, modifier = Modifier.size(48.dp)) {
      Icon(Icons.Outlined.Sync, contentDescription = strings.text("android.chat.sync"), tint = GaPrimary)
    }
  }
  HorizontalDivider(color = GaBorder)
}

@Composable
private fun ChatMessageBubble(message: RuntimeMessage) {
  val strings = LocalAppStrings.current
  val user = message.role == "user"
  Column(
    modifier = Modifier.fillMaxWidth(),
    horizontalAlignment = if (user) Alignment.End else Alignment.Start,
  ) {
    if (!user) {
      Text(
        text = strings.text("android.chat.runtime"),
        color = GaTextSecondary,
        fontFamily = FontFamily.Monospace,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
      )
    }
    Box(
      modifier = Modifier
        .fillMaxWidth(if (user) 0.85f else 0.9f)
        .clip(GaLargeShape)
        .background(if (user) GaSurfaceMuted else GaSurface)
        .then(if (user) Modifier else Modifier.border(1.dp, GaBorder, GaLargeShape))
        .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
      Text(
        text = message.content,
        color = GaText,
        fontSize = 14.sp,
        lineHeight = 20.sp,
      )
    }
  }
}

@Composable
private fun RunningTurnRow() {
  val strings = LocalAppStrings.current
  Row(
    modifier = Modifier
      .fillMaxWidth(0.9f)
      .height(46.dp)
      .background(GaAmberContainer, GaLargeShape)
      .border(1.dp, GaAmber, GaLargeShape)
      .padding(horizontal = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    CircularProgressIndicator(
      modifier = Modifier.size(20.dp),
      color = GaAmber,
      strokeWidth = 2.dp,
    )
    Text(
      text = strings.text("android.chat.running"),
      color = GaAmberText,
      fontWeight = FontWeight.Medium,
      fontSize = 14.sp,
    )
  }
}

@Composable
private fun TurnErrorRow(message: String) {
  Text(
    text = message,
    color = MaterialTheme.colorScheme.error,
    fontSize = 13.sp,
    lineHeight = 18.sp,
    modifier = Modifier
      .fillMaxWidth()
      .background(MaterialTheme.colorScheme.errorContainer, GaLargeShape)
      .padding(12.dp),
  )
}

@Composable
private fun ChatComposer(
  draft: String,
  onDraftChange: (String) -> Unit,
  onSend: () -> Unit,
  enabled: Boolean,
  sending: Boolean,
  onAttach: () -> Unit,
) {
  val strings = LocalAppStrings.current
  val sendHighlighted = sending || (enabled && draft.isNotBlank())
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .height(80.dp)
      .background(GaSurface),
  ) {
    HorizontalDivider(color = GaBorder)
    Row(
      modifier = Modifier
        .fillMaxSize()
        .padding(horizontal = 16.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      IconButton(onClick = onAttach, modifier = Modifier.size(48.dp)) {
        Icon(Icons.Outlined.AttachFile, contentDescription = strings.text("android.chat.attach"), tint = GaTextSecondary)
      }
      BasicTextField(
        value = draft,
        onValueChange = onDraftChange,
        enabled = enabled,
        textStyle = TextStyle(
          color = GaText,
          fontSize = 14.sp,
          lineHeight = 20.sp,
        ),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
        keyboardActions = KeyboardActions(onSend = { onSend() }),
        modifier = Modifier
          .weight(1f)
          .heightIn(min = 48.dp, max = 64.dp)
          .background(GaSurfaceMuted, GaLargeShape)
          .border(1.dp, GaBorder, GaLargeShape)
          .padding(horizontal = 12.dp, vertical = 14.dp),
        decorationBox = { inner ->
          Box {
            if (draft.isEmpty()) {
              Text(strings.text("android.chat.placeholder"), color = GaTextSecondary, fontSize = 14.sp)
            }
            inner()
          }
        },
      )
      IconButton(
        onClick = onSend,
        enabled = enabled && draft.isNotBlank(),
        modifier = Modifier
          .size(48.dp)
          .background(
            if (sendHighlighted) GaPrimary else GaSurfaceMuted,
            GaLargeShape,
          ),
      ) {
        Icon(
          Icons.AutoMirrored.Filled.Send,
          contentDescription = strings.text("android.chat.send"),
          tint = if (sendHighlighted) MaterialTheme.colorScheme.onPrimary else GaTextSecondary,
        )
      }
    }
  }
}

package com.agentweave.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.agentweave.mobile.IdentityPromptPhase

@Composable
fun IdentityLoadingScreen(modifier: Modifier = Modifier) {
  val strings = LocalAppStrings.current
  Box(
    modifier = modifier.fillMaxSize().background(GaSurface),
    contentAlignment = Alignment.Center,
  ) {
    Column(
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.spacedBy(16.dp),
      modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
    ) {
      CircularProgressIndicator(
        modifier = Modifier.size(28.dp),
        color = GaPrimaryActive,
        strokeWidth = 2.dp,
      )
      Text(
        strings.text("identity.checkingSession"),
        color = GaTextSecondary,
        fontSize = 14.sp,
        lineHeight = 20.sp,
      )
    }
  }
}

@Composable
fun IdentityRequiredScreen(
  appDisplayName: String,
  phase: IdentityPromptPhase,
  errorMessage: String?,
  onSignIn: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val strings = LocalAppStrings.current
  val waiting = phase == IdentityPromptPhase.WaitingForBrowser ||
    phase == IdentityPromptPhase.Completing
  val statusText = when (phase) {
    IdentityPromptPhase.WaitingForBrowser -> strings.text("identity.waitingForBrowser")
    IdentityPromptPhase.Completing -> strings.text("identity.completingSignIn")
    IdentityPromptPhase.Expired -> strings.text("identity.sessionExpired")
    IdentityPromptPhase.Unavailable -> strings.text("identity.unavailable")
    IdentityPromptPhase.SignedOut -> strings.text("identity.signInDescription")
  }

  IdentityPageFrame(modifier) {
    IdentityHeader(appDisplayName)
    IdentityCard {
      Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Box(
          modifier = Modifier
            .size(42.dp)
            .background(GaSurfaceMuted, CircleShape)
            .border(1.dp, GaBorder, CircleShape),
          contentAlignment = Alignment.Center,
        ) {
          if (waiting) {
            CircularProgressIndicator(
              modifier = Modifier.size(20.dp),
              strokeWidth = 2.dp,
              color = GaPrimaryActive,
            )
          } else {
            Icon(
              Icons.Outlined.Security,
              contentDescription = null,
              tint = if (phase == IdentityPromptPhase.Unavailable) {
                MaterialTheme.colorScheme.error
              } else {
                GaReady
              },
              modifier = Modifier.size(22.dp),
            )
          }
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
          Text(
            strings.text("identity.secureSession"),
            color = GaText,
            fontSize = 15.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.SemiBold,
          )
          Text(
            when (phase) {
              IdentityPromptPhase.Expired -> strings.text("identity.signInAgain")
              IdentityPromptPhase.Unavailable -> strings.text("identity.tryAgain")
              else -> strings.text("identity.signIn")
            },
            color = GaTextSecondary,
            fontSize = 13.sp,
            lineHeight = 18.sp,
          )
        }
      }
      Text(
        statusText,
        color = if (phase == IdentityPromptPhase.Unavailable) {
          MaterialTheme.colorScheme.error
        } else {
          GaTextSecondary
        },
        fontSize = 14.sp,
        lineHeight = 21.sp,
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
      )
      errorMessage?.let { message -> IdentityErrorMessage(message) }
      Button(
        onClick = onSignIn,
        enabled = !waiting,
        modifier = Modifier.fillMaxWidth().height(48.dp),
        shape = GaLargeShape,
        colors = ButtonDefaults.buttonColors(containerColor = GaPrimaryActive),
      ) {
        Text(
          if (phase == IdentityPromptPhase.Expired) {
            strings.text("identity.signInAgain")
          } else if (phase == IdentityPromptPhase.Unavailable) {
            strings.text("identity.tryAgain")
          } else {
            strings.text("identity.signIn")
          },
          fontWeight = FontWeight.SemiBold,
        )
      }
    }
    IdentityPrivacyNote()
  }
}

@Composable
fun IdentityFailureScreen(
  appDisplayName: String,
  message: String,
  onRetry: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val strings = LocalAppStrings.current
  IdentityPageFrame(modifier) {
    IdentityHeader(appDisplayName)
    IdentityCard {
      IdentityErrorMessage(message)
      OutlinedButton(
        onClick = onRetry,
        modifier = Modifier.fillMaxWidth().height(48.dp),
        shape = GaLargeShape,
      ) {
        Text(strings.text("identity.tryAgain"), fontWeight = FontWeight.SemiBold)
      }
    }
    IdentityPrivacyNote()
  }
}

@Composable
private fun IdentityPageFrame(
  modifier: Modifier,
  content: @Composable ColumnScope.() -> Unit,
) {
  BoxWithConstraints(
    modifier = modifier.fillMaxSize().background(GaSurfaceSubtle),
    contentAlignment = Alignment.Center,
  ) {
    val horizontalPadding = if (maxWidth >= 720.dp) 48.dp else 20.dp
    Column(
      modifier = Modifier
        .widthIn(max = 560.dp)
        .fillMaxWidth()
        .padding(horizontal = horizontalPadding, vertical = 32.dp),
      verticalArrangement = Arrangement.spacedBy(20.dp),
      content = content,
    )
  }
}

@Composable
private fun IdentityHeader(appDisplayName: String) {
  val strings = LocalAppStrings.current
  Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Box(
        modifier = Modifier
          .width(36.dp)
          .height(4.dp)
          .background(GaPrimaryActive, CircleShape),
      )
      Spacer(modifier = Modifier.width(8.dp))
      Box(
        modifier = Modifier
          .width(10.dp)
          .height(4.dp)
          .background(GaReady, CircleShape),
      )
    }
    Text(
      strings.text("identity.signInTo", mapOf("app" to appDisplayName)),
      color = GaText,
      fontSize = 28.sp,
      lineHeight = 34.sp,
      fontWeight = FontWeight.SemiBold,
    )
    Text(
      strings.text("identity.signInDescription"),
      color = GaTextSecondary,
      fontSize = 15.sp,
      lineHeight = 23.sp,
    )
  }
}

@Composable
private fun IdentityCard(content: @Composable ColumnScope.() -> Unit) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .background(GaSurface, GaLargeShape)
      .border(1.dp, GaBorder, GaLargeShape)
      .padding(20.dp),
    verticalArrangement = Arrangement.spacedBy(18.dp),
    content = content,
  )
}

@Composable
private fun IdentityErrorMessage(message: String) {
  Text(
    message,
    color = MaterialTheme.colorScheme.error,
    fontSize = 13.sp,
    lineHeight = 19.sp,
    modifier = Modifier
      .fillMaxWidth()
      .background(MaterialTheme.colorScheme.errorContainer, GaLargeShape)
      .padding(12.dp)
      .semantics { liveRegion = LiveRegionMode.Assertive },
  )
}

@Composable
private fun IdentityPrivacyNote() {
  val strings = LocalAppStrings.current
  Row(
    horizontalArrangement = Arrangement.spacedBy(10.dp),
    verticalAlignment = Alignment.Top,
    modifier = Modifier.padding(horizontal = 4.dp),
  ) {
    Icon(
      Icons.Outlined.Lock,
      contentDescription = null,
      tint = GaTextSecondary,
      modifier = Modifier.size(17.dp),
    )
    Text(
      strings.text("identity.privacyNote"),
      color = GaTextSecondary,
      fontSize = 12.sp,
      lineHeight = 18.sp,
    )
  }
}

package com.agentweave.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
internal fun AccountSettingsCard(
  accountId: String,
  expiresAt: String,
  onSwitchAccount: () -> Unit,
  onSignOut: () -> Unit,
  onClearAccountData: () -> Unit,
) {
  val strings = LocalAppStrings.current
  var confirmClear by remember { mutableStateOf(false) }
  Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
    Text(
      strings.text("identity.accountTitle"),
      color = GaText,
      fontSize = 15.sp,
      lineHeight = 18.sp,
      fontWeight = FontWeight.Medium,
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .background(GaSurfaceMuted, GaLargeShape)
        .border(1.dp, GaBorder, GaLargeShape)
        .padding(16.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      AccountIdentityRow(accountId)
      Text(
        strings.text("identity.expiresAt", mapOf("time" to readableIdentityExpiry(expiresAt))),
        color = GaTextSecondary,
        fontSize = 13.sp,
        lineHeight = 19.sp,
      )
      Text(
        strings.text("identity.accountDescription"),
        color = GaTextSecondary,
        fontSize = 13.sp,
        lineHeight = 19.sp,
      )
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        OutlinedButton(
          onClick = onSwitchAccount,
          modifier = Modifier.weight(1f).height(48.dp),
          shape = GaLargeShape,
        ) {
          Text(strings.text("identity.switchAccount"))
        }
        OutlinedButton(
          onClick = onSignOut,
          modifier = Modifier.weight(1f).height(48.dp),
          shape = GaLargeShape,
        ) {
          Text(strings.text("identity.signOut"))
        }
      }
      OutlinedButton(
        onClick = { confirmClear = true },
        modifier = Modifier.fillMaxWidth().height(48.dp),
        shape = GaLargeShape,
        colors = ButtonDefaults.outlinedButtonColors(
          contentColor = MaterialTheme.colorScheme.error,
        ),
      ) {
        Icon(
          Icons.Outlined.DeleteOutline,
          contentDescription = null,
          modifier = Modifier.size(18.dp),
        )
        Text(strings.text("identity.clearLocalData"))
      }
    }
  }

  if (confirmClear) {
    AlertDialog(
      onDismissRequest = { confirmClear = false },
      shape = GaLargeShape,
      title = { Text(strings.text("identity.clearLocalDataTitle")) },
      text = { Text(strings.text("identity.clearLocalDataDescription")) },
      confirmButton = {
        Button(
          onClick = {
            confirmClear = false
            onClearAccountData()
          },
          colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.error,
            contentColor = MaterialTheme.colorScheme.onError,
          ),
          shape = GaLargeShape,
        ) {
          Text(strings.text("identity.clearLocalDataConfirm"))
        }
      },
      dismissButton = {
        OutlinedButton(
          onClick = { confirmClear = false },
          shape = GaLargeShape,
        ) {
          Text(strings.text("common.cancel"))
        }
      },
    )
  }
}

@Composable
private fun AccountIdentityRow(accountId: String) {
  val strings = LocalAppStrings.current
  Row(
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Box(
      modifier = Modifier
        .size(40.dp)
        .background(GaSurface, GaLargeShape)
        .border(1.dp, GaBorder, GaLargeShape),
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        Icons.Outlined.AccountCircle,
        contentDescription = null,
        tint = GaReady,
        modifier = Modifier.size(22.dp),
      )
    }
    Column(
      modifier = Modifier.weight(1f),
      verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
      Text(
        strings.text("identity.signedIn"),
        color = GaText,
        fontSize = 15.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.SemiBold,
      )
      Text(
        strings.text(
          "identity.accountReference",
          mapOf("reference" to accountId.takeLast(10)),
        ),
        color = GaTextSecondary,
        fontFamily = LocalGaMonoFontFamily.current,
        fontSize = 12.sp,
        lineHeight = 18.sp,
      )
    }
  }
}

private fun readableIdentityExpiry(value: String): String = runCatching {
  java.time.format.DateTimeFormatter
    .ofPattern("yyyy-MM-dd HH:mm")
    .withZone(java.time.ZoneId.systemDefault())
    .format(java.time.Instant.parse(value))
}.getOrDefault(value)

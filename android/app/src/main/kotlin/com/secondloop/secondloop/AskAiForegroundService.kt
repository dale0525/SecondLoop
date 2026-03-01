package com.secondloop.secondloop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AskAiForegroundService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    return when (intent?.action) {
      ACTION_STOP -> {
        stopForegroundCompat()
        stopSelf()
        START_NOT_STICKY
      }
      else -> {
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        START_STICKY
      }
    }
  }

  private fun ensureChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
      ?: return

    val channel = NotificationChannel(
      CHANNEL_ID,
      getString(R.string.ask_ai_foreground_channel_name),
      NotificationManager.IMPORTANCE_LOW,
    ).apply {
      description = getString(R.string.ask_ai_foreground_channel_description)
      setShowBadge(false)
    }

    manager.createNotificationChannel(channel)
  }

  private fun buildNotification(): Notification {
    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
      ?.apply {
        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
      }

    val contentIntent = if (launchIntent == null) {
      null
    } else {
      PendingIntent.getActivity(
        this,
        0,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
      )
    }

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_stat_notify)
      .setContentTitle(getString(R.string.ask_ai_foreground_title))
      .setContentText(getString(R.string.ask_ai_foreground_text))
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setContentIntent(contentIntent)
      .build()
  }

  private fun pendingIntentImmutableFlag(): Int {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      PendingIntent.FLAG_IMMUTABLE
    } else {
      0
    }
  }

  @Suppress("DEPRECATION")
  private fun stopForegroundCompat() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      stopForeground(true)
    }
  }

  companion object {
    private const val CHANNEL_ID = "ask_ai_foreground_v1"
    private const val NOTIFICATION_ID = 2026030101

    private const val ACTION_START =
      "com.secondloop.secondloop.action.ASK_AI_FOREGROUND_START"
    private const val ACTION_STOP =
      "com.secondloop.secondloop.action.ASK_AI_FOREGROUND_STOP"

    fun startIntent(context: Context): Intent {
      return Intent(context, AskAiForegroundService::class.java).apply {
        action = ACTION_START
      }
    }

    fun stopIntent(context: Context): Intent {
      return Intent(context, AskAiForegroundService::class.java).apply {
        action = ACTION_STOP
      }
    }
  }
}

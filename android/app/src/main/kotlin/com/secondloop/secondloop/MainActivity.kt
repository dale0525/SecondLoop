package com.secondloop.secondloop

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
  private val pendingShares = mutableListOf<Map<String, String>>()
  private var shareChannel: MethodChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    shareChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/share_intent").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "consumePendingShares" -> {
              val shares = pendingShares.toList()
              pendingShares.clear()
              result.success(shares)
            }
            else -> result.notImplemented()
          }
        }
      }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleShareIntent(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleShareIntent(intent)
  }

  private fun handleShareIntent(intent: Intent?) {
    if (intent == null) return

    val type = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_TYPE)
    val content = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_CONTENT)
    if (type.isNullOrBlank() || content.isNullOrBlank()) return

    val mimeType = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_MIME_TYPE)
    val payload = mutableMapOf("type" to type, "content" to content)
    if (!mimeType.isNullOrBlank()) {
      payload["mimeType"] = mimeType
    }
    pendingShares.add(payload)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_TYPE)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_CONTENT)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_MIME_TYPE)
  }
}

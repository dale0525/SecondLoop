package com.secondloop.secondloop

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.io.File

class ShareReceiverActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    val shareIntent = intent
    if (shareIntent != null && Intent.ACTION_SEND == shareIntent.action) {
      val mimeType = shareIntent.type ?: ""

      if (mimeType == "text/plain" || mimeType == "text/uri-list" || mimeType.startsWith("text/")) {
        val sharedText = shareIntent.getStringExtra(Intent.EXTRA_TEXT)
        if (!sharedText.isNullOrBlank()) {
          val type = if (mimeType == "text/uri-list") "url" else "text"
          forwardToMainActivity(type, sharedText, null)
        }
      }

      if (mimeType.startsWith("image/")) {
        val uri = shareIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (uri != null) {
          val resolvedMimeType = mimeType.ifBlank { contentResolver.getType(uri) ?: "" }
          val cached = copyToCache(uri)
          if (!cached.isNullOrBlank()) {
            forwardToMainActivity("image", cached, resolvedMimeType)
          }
        }
      }
    }

    finish()
  }

  private fun forwardToMainActivity(type: String, content: String, mimeType: String?) {
    val launchIntent =
      Intent(this, MainActivity::class.java).apply {
        addFlags(
          Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        putExtra(EXTRA_SHARE_TYPE, type)
        putExtra(EXTRA_SHARE_CONTENT, content)
        if (!mimeType.isNullOrBlank()) {
          putExtra(EXTRA_SHARE_MIME_TYPE, mimeType)
        }
      }

    startActivity(launchIntent)
  }

  private fun copyToCache(uri: Uri): String? {
    try {
      val outDir = File(cacheDir, "share_intent")
      outDir.mkdirs()
      val outFile = File(outDir, "shared_${System.currentTimeMillis()}.bin")

      contentResolver.openInputStream(uri)?.use { input ->
        outFile.outputStream().use { output ->
          input.copyTo(output)
        }
      } ?: return null

      return outFile.absolutePath
    } catch (_: Exception) {
      return null
    }
  }

  companion object {
    const val EXTRA_SHARE_TYPE = "secondloop_share_type"
    const val EXTRA_SHARE_CONTENT = "secondloop_share_content"
    const val EXTRA_SHARE_MIME_TYPE = "secondloop_share_mime_type"
  }
}

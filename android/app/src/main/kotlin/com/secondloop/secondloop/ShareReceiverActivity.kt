package com.secondloop.secondloop

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
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
          val trimmed = sharedText.trim()
          val isUrl = mimeType == "text/uri-list" || looksLikeHttpUrl(trimmed)
          val type = if (isUrl) "url" else "text"
          forwardToMainActivity(type, trimmed, null, null)
        }
      }

      val uri = shareIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
      if (uri != null) {
        val resolvedMimeType = mimeType.ifBlank { contentResolver.getType(uri) ?: "" }
        val filename = queryDisplayName(uri)
        val cached = copyToCache(uri, filename)
        if (!cached.isNullOrBlank()) {
          val type = if (resolvedMimeType.startsWith("image/")) "image" else "file"
          forwardToMainActivity(type, cached, resolvedMimeType, filename)
        }
      }
    }

    finish()
  }

  private fun forwardToMainActivity(type: String, content: String, mimeType: String?, filename: String?) {
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
        if (!filename.isNullOrBlank()) {
          putExtra(EXTRA_SHARE_FILENAME, filename)
        }
      }

    startActivity(launchIntent)
  }

  private fun sanitizeFilename(filename: String): String {
    val trimmed = filename.trim()
    if (trimmed.isEmpty()) return "file"
    val safe = trimmed.replace(Regex("[^A-Za-z0-9._-]+"), "_")
    if (safe.isEmpty()) return "file"
    return safe.take(100)
  }

  private fun queryDisplayName(uri: Uri): String? {
    try {
      contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (idx < 0) return null
        if (!cursor.moveToFirst()) return null
        return cursor.getString(idx)
      }
      return null
    } catch (_: Exception) {
      return null
    }
  }

  private fun looksLikeHttpUrl(value: String): Boolean {
    val trimmed = value.trim()
    if (trimmed.isEmpty()) return false
    try {
      val uri = Uri.parse(trimmed)
      val scheme = uri.scheme ?: return false
      if (scheme != "http" && scheme != "https") return false
      val host = uri.host ?: return false
      if (host.isBlank()) return false
      return true
    } catch (_: Exception) {
      return false
    }
  }

  private fun copyToCache(uri: Uri, filename: String?): String? {
    try {
      val outDir = File(cacheDir, "share_intent")
      outDir.mkdirs()
      val safeName = if (filename.isNullOrBlank()) "shared.bin" else sanitizeFilename(filename)
      val outFile = File(outDir, "shared_${System.currentTimeMillis()}_${safeName}")

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
    const val EXTRA_SHARE_FILENAME = "secondloop_share_filename"
  }
}

package com.secondloop.secondloop

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import java.io.File
import java.util.Locale

class ShareReceiverActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    val shareIntent = intent
    when (shareIntent?.action) {
      Intent.ACTION_SEND -> handleSingleShare(shareIntent)
      Intent.ACTION_SEND_MULTIPLE -> handleMultipleShare(shareIntent)
    }

    finish()
  }

  private fun handleSingleShare(shareIntent: Intent) {
    val sharedMimeType = normalizeMimeType(shareIntent.type)

    if (sharedMimeType == "text/plain" ||
      sharedMimeType == "text/uri-list" ||
      sharedMimeType.startsWith("text/")
    ) {
      val sharedText = shareIntent.getStringExtra(Intent.EXTRA_TEXT)
      if (!sharedText.isNullOrBlank()) {
        val trimmed = sharedText.trim()
        val isUrl = sharedMimeType == "text/uri-list" || looksLikeHttpUrl(trimmed)
        val type = if (isUrl) "url" else "text"
        forwardToMainActivity(type, trimmed, null, null)
      }
    }

    val uri = shareIntent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
    if (uri != null) {
      forwardUriShare(uri, sharedMimeType)
    }
  }

  private fun handleMultipleShare(shareIntent: Intent) {
    val sharedMimeType = normalizeMimeType(shareIntent.type)
    val uris = shareIntent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
    if (uris.isNullOrEmpty()) return

    for (uri in uris) {
      forwardUriShare(uri, sharedMimeType)
    }
  }

  private fun forwardUriShare(uri: Uri, sharedMimeType: String) {
    val filename = queryDisplayName(uri)
    val cached = copyToCache(uri, filename)
    if (cached.isNullOrBlank()) return

    val resolvedMimeType = resolveMimeType(uri, sharedMimeType, filename)
    val type = if (resolvedMimeType.startsWith("image/")) "image" else "file"
    forwardToMainActivity(type, cached, resolvedMimeType, filename)
  }

  private fun normalizeMimeType(mimeType: String?): String {
    return mimeType?.trim()?.lowercase(Locale.ROOT).orEmpty()
  }

  private fun resolveMimeType(uri: Uri, sharedMimeType: String, filename: String?): String {
    if (sharedMimeType.isNotBlank() && sharedMimeType != "*/*") {
      return sharedMimeType
    }

    val fromResolver = normalizeMimeType(contentResolver.getType(uri))
    if (fromResolver.isNotBlank()) {
      return fromResolver
    }

    val fromFilename = inferMimeTypeFromFilename(filename)
    if (!fromFilename.isNullOrBlank()) {
      return fromFilename
    }

    return "application/octet-stream"
  }

  private fun inferMimeTypeFromFilename(filename: String?): String? {
    val lower = filename?.trim()?.lowercase(Locale.ROOT)
    if (lower.isNullOrBlank()) return null

    if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg"
    if (lower.endsWith(".png")) return "image/png"
    if (lower.endsWith(".webp")) return "image/webp"
    if (lower.endsWith(".gif")) return "image/gif"
    if (lower.endsWith(".heic")) return "image/heic"
    if (lower.endsWith(".heif")) return "image/heif"

    if (lower.endsWith(".pdf")) return "application/pdf"
    if (lower.endsWith(".txt")) return "text/plain"
    if (lower.endsWith(".md")) return "text/markdown"
    if (lower.endsWith(".json")) return "application/json"
    if (lower.endsWith(".csv")) return "text/csv"

    if (lower.endsWith(".mp3")) return "audio/mpeg"
    if (lower.endsWith(".m4a")) return "audio/mp4"
    if (lower.endsWith(".wav")) return "audio/wav"
    if (lower.endsWith(".aac")) return "audio/aac"
    if (lower.endsWith(".flac")) return "audio/flac"
    if (lower.endsWith(".ogg")) return "audio/ogg"

    if (lower.endsWith(".mp4")) return "video/mp4"
    if (lower.endsWith(".mov")) return "video/quicktime"
    if (lower.endsWith(".webm")) return "video/webm"
    if (lower.endsWith(".mkv")) return "video/x-matroska"
    if (lower.endsWith(".avi")) return "video/x-msvideo"

    return null
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

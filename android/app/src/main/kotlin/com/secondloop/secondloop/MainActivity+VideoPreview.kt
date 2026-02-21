package com.secondloop.secondloop

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import kotlin.math.ceil

fun MainActivity.handleExtractPreviewPosterJpeg(
  call: MethodCall,
  result: MethodChannel.Result
) {
  val args = call.arguments as? Map<*, *>
  val inputPath = (args?.get("input_path") as? String)?.trim().orEmpty()
  val outputPath = (args?.get("output_path") as? String)?.trim().orEmpty()
  if (inputPath.isEmpty() || outputPath.isEmpty()) {
    result.success(false)
    return
  }

  Thread {
    val ok = try {
      extractPreviewPosterJpeg(inputPath = inputPath, outputPath = outputPath)
    } catch (_: Throwable) {
      false
    }
    runOnUiThread {
      result.success(ok)
    }
  }.start()
}

fun MainActivity.handleExtractPreviewFramesJpeg(
  call: MethodCall,
  result: MethodChannel.Result
) {
  val args = call.arguments as? Map<*, *>
  val inputPath = (args?.get("input_path") as? String)?.trim().orEmpty()
  val outputDirPath = (args?.get("output_dir") as? String)?.trim().orEmpty()
  val maxKeyframes = ((args?.get("max_keyframes") as? Number)?.toInt() ?: 24).coerceIn(1, 48)
  val frameIntervalSeconds =
    ((args?.get("frame_interval_seconds") as? Number)?.toInt() ?: 8).coerceIn(1, 600)
  if (inputPath.isEmpty() || outputDirPath.isEmpty()) {
    result.success(null)
    return
  }

  Thread {
    val payload = try {
      extractPreviewFramesJpeg(
        inputPath = inputPath,
        outputDirPath = outputDirPath,
        maxKeyframes = maxKeyframes,
        frameIntervalSeconds = frameIntervalSeconds
      )
    } catch (_: Throwable) {
      null
    }
    runOnUiThread {
      result.success(payload)
    }
  }.start()
}

private fun extractPreviewFramesJpeg(
  inputPath: String,
  outputDirPath: String,
  maxKeyframes: Int,
  frameIntervalSeconds: Int
): Map<String, Any?>? {
  val inputFile = File(inputPath)
  if (!inputFile.exists() || !inputFile.isFile) return null

  val outputDir = File(outputDirPath)
  outputDir.mkdirs()

  var retriever: MediaMetadataRetriever? = null
  try {
    retriever = MediaMetadataRetriever()
    retriever.setDataSource(inputPath)

    val durationMs =
      retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
        ?.toLongOrNull()
        ?.coerceAtLeast(0L)
        ?: 0L
    val baseIntervalMs = frameIntervalSeconds.toLong() * 1000L
    val adaptiveIntervalMs = if (durationMs > 0L && maxKeyframes > 0) {
      val spreadInterval = ceil(durationMs.toDouble() / maxKeyframes.toDouble()).toLong()
        .coerceAtLeast(1000L)
      maxOf(baseIntervalMs, spreadInterval)
    } else {
      baseIntervalMs
    }
    val posterPath = "${outputDir.absolutePath}/poster.jpg"
    val posterOk = writeFrameAsJpeg(retriever, 0L, posterPath)

    val keyframes = mutableListOf<Map<String, Any>>()
    val seenHashes = mutableSetOf<Int>()
    var tMs = 0L
    val maxDurationMs = if (durationMs > 0L) durationMs else adaptiveIntervalMs * maxKeyframes
    while (keyframes.size < maxKeyframes && tMs <= maxDurationMs) {
      val outputPath =
        "${outputDir.absolutePath}/keyframe_${String.format(Locale.US, "%03d", keyframes.size)}.jpg"
      if (writeFrameAsJpeg(retriever, tMs, outputPath)) {
        val frameFile = File(outputPath)
        val frameBytes = runCatching { frameFile.readBytes() }.getOrNull()
        if (frameBytes != null && frameBytes.isNotEmpty()) {
          val hash = frameBytes.contentHashCode()
          if (seenHashes.add(hash)) {
            keyframes.add(
              mapOf(
                "path" to outputPath,
                "t_ms" to tMs
              )
            )
          } else {
            frameFile.delete()
          }
        }
      }
      if (adaptiveIntervalMs <= 0L) break
      tMs += adaptiveIntervalMs
    }

    if (keyframes.isEmpty() && posterOk) {
      keyframes.add(
        mapOf(
          "path" to posterPath,
          "t_ms" to 0L
        )
      )
    }

    return mapOf(
      "poster_path" to if (posterOk) posterPath else null,
      "keyframes" to keyframes
    )
  } catch (_: Throwable) {
    return null
  } finally {
    try {
      retriever?.release()
    } catch (_: Throwable) {
      // ignore
    }
  }
}

private fun extractPreviewPosterJpeg(inputPath: String, outputPath: String): Boolean {
  val inputFile = File(inputPath)
  if (!inputFile.exists() || !inputFile.isFile) return false

  var retriever: MediaMetadataRetriever? = null
  try {
    retriever = MediaMetadataRetriever()
    retriever.setDataSource(inputPath)
    return writeFrameAsJpeg(retriever, 0L, outputPath)
  } catch (_: Throwable) {
    return false
  } finally {
    try {
      retriever?.release()
    } catch (_: Throwable) {
      // ignore
    }
  }
}

private fun writeFrameAsJpeg(
  retriever: MediaMetadataRetriever,
  timeMs: Long,
  outputPath: String
): Boolean {
  val outputFile = File(outputPath)
  outputFile.parentFile?.mkdirs()
  if (outputFile.exists()) {
    outputFile.delete()
  }

  var bitmap: Bitmap? = null
  try {
    val clampedTimeMs = if (timeMs < 0L) 0L else timeMs
    val timeUs = clampedTimeMs * 1000L
    bitmap = retriever.getFrameAtTime(
      timeUs,
      MediaMetadataRetriever.OPTION_CLOSEST
    )
    if (bitmap == null) {
      bitmap = retriever.getFrameAtTime(
        timeUs,
        MediaMetadataRetriever.OPTION_CLOSEST_SYNC
      )
    }
    val frame = bitmap ?: return false

    FileOutputStream(outputFile).use { output ->
      if (!frame.compress(Bitmap.CompressFormat.JPEG, 82, output)) {
        return false
      }
      output.flush()
    }
    return outputFile.exists() && outputFile.length() > 0
  } catch (_: Throwable) {
    return false
  } finally {
    try {
      bitmap?.recycle()
    } catch (_: Throwable) {
      // ignore
    }
  }
}

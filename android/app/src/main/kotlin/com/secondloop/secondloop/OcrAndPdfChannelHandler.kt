package com.secondloop.secondloop

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Locale

class OcrAndPdfChannelHandler(
  private val cacheDir: File,
) {
  private data class PdfRenderPreset(
    val id: String,
    val maxPages: Int,
    val dpi: Int,
  )

  private val commonPdfOcrPreset = PdfRenderPreset(
    id = "common_ocr_v1",
    maxPages = 10_000,
    dpi = 180,
  )

  fun handle(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "ocrPdf" -> handleOcrPdf(call, result)
      "ocrImage" -> handleOcrImage(call, result)
      "renderPdfToLongImage" -> handleRenderPdfToLongImage(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleOcrPdf(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val bytes = args?.get("bytes") as? ByteArray
    if (bytes == null || bytes.isEmpty()) {
      result.success(null)
      return
    }

    val maxPages = normalizePositiveInt(args["max_pages"], fallback = 200, upperBound = 10_000)
    val dpi = normalizePositiveInt(args["dpi"], fallback = 180, upperBound = 600)
    val languageHints = (args["language_hints"] as? String)?.trim().orEmpty().ifEmpty { "device_plus_en" }
    Thread {
      val payload =
        try {
          runPdfOcrWithMlKit(bytes, maxPages, languageHints, dpi)
        } catch (_: Throwable) {
          null
        }
      Handler(Looper.getMainLooper()).post {
        result.success(payload)
      }
    }.start()
  }

  private fun handleOcrImage(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val bytes = args?.get("bytes") as? ByteArray
    if (bytes == null || bytes.isEmpty()) {
      result.success(null)
      return
    }

    val languageHints = (args["language_hints"] as? String)?.trim().orEmpty().ifEmpty { "device_plus_en" }
    Thread {
      val payload =
        try {
          runImageOcrWithMlKit(bytes, languageHints)
        } catch (_: Throwable) {
          null
        }
      Handler(Looper.getMainLooper()).post {
        result.success(payload)
      }
    }.start()
  }

  private fun handleRenderPdfToLongImage(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val bytes = args?.get("bytes") as? ByteArray
    if (bytes == null || bytes.isEmpty()) {
      result.success(null)
      return
    }

    val preset = resolvePdfRenderPreset(args)

    Thread {
      val payload =
        try {
          runRenderPdfToLongImage(bytes, preset.maxPages, preset.dpi)
        } catch (_: Throwable) {
          null
        }
      Handler(Looper.getMainLooper()).post {
        result.success(payload)
      }
    }.start()
  }

  private fun normalizePositiveInt(raw: Any?, fallback: Int, upperBound: Int): Int {
    val value =
      when (raw) {
        is Int -> raw
        is Long -> raw.toInt()
        is Double -> raw.toInt()
        is Float -> raw.toInt()
        is String -> raw.trim().toIntOrNull() ?: fallback
        else -> fallback
      }
    return value.coerceIn(1, upperBound)
  }

  private fun resolvePdfRenderPreset(args: Map<*, *>?): PdfRenderPreset {
    val presetId =
      (args?.get("ocr_model_preset") as? String)?.trim()?.lowercase(Locale.US).orEmpty()
    if (presetId == commonPdfOcrPreset.id) {
      return commonPdfOcrPreset
    }

    val maxPages = normalizePositiveInt(args?.get("max_pages"), fallback = commonPdfOcrPreset.maxPages, upperBound = 10_000)
    val dpi = normalizePositiveInt(args?.get("dpi"), fallback = commonPdfOcrPreset.dpi, upperBound = 600)
    return PdfRenderPreset(
      id = if (presetId.isEmpty()) commonPdfOcrPreset.id else presetId,
      maxPages = maxPages,
      dpi = dpi,
    )
  }

  private fun selectTextRecognizer(languageHints: String): TextRecognizer {
    val normalizedHints = languageHints.trim().lowercase(Locale.US)
    val resolvedHints =
      if (normalizedHints == "device_plus_en") {
        when (Locale.getDefault().language.trim().lowercase(Locale.US)) {
          "zh" -> "zh_en"
          "ja" -> "ja_en"
          "ko" -> "ko_en"
          else -> "en"
        }
      } else {
        normalizedHints
      }

    return when (resolvedHints) {
      "zh_en" -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
      "zh_strict" -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
      "ja_en" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
      "ko_en" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
      else -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }
  }

  private fun runPdfOcrWithMlKit(
    pdfBytes: ByteArray,
    maxPages: Int,
    languageHints: String,
    dpi: Int,
  ): Map<String, Any>? {
    if (pdfBytes.isEmpty()) return null

    var inputFile: File? = null
    var descriptor: ParcelFileDescriptor? = null
    var renderer: PdfRenderer? = null
    val recognizer = selectTextRecognizer(languageHints)

    try {
      inputFile = File.createTempFile("secondloop_pdf_ocr_", ".pdf", cacheDir)
      inputFile.writeBytes(pdfBytes)

      descriptor = ParcelFileDescriptor.open(inputFile, ParcelFileDescriptor.MODE_READ_ONLY)
      renderer = PdfRenderer(descriptor)
      val pageCount = renderer.pageCount
      if (pageCount <= 0) return null

      val targetPages = pageCount.coerceAtMost(maxPages)
      val blocks = mutableListOf<String>()
      var processedPages = 0

      for (index in 0 until targetPages) {
        val page = renderer.openPage(index)
        try {
          val scale = (dpi.toFloat() / 72f).coerceIn(1.0f, 6.0f)
          val width = (page.width * scale).toInt().coerceAtLeast(1)
          val height = (page.height * scale).toInt().coerceAtLeast(1)
          val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
          try {
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val text =
              try {
                Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0))).text
              } catch (_: Throwable) {
                ""
              }.trim()
            processedPages += 1
            if (text.isNotEmpty()) {
              blocks.add("[page ${index + 1}]\n$text")
            }
          } finally {
            bitmap.recycle()
          }
        } finally {
          page.close()
        }
      }

      val full = blocks.joinToString(separator = "\n\n")
      val fullTruncated = truncateUtf8(full, maxBytes = 256 * 1024)
      val excerpt = truncateUtf8(fullTruncated, maxBytes = 8 * 1024)
      val isTruncated = processedPages < pageCount || fullTruncated != full

      return mapOf(
        "ocr_text_full" to fullTruncated,
        "ocr_text_excerpt" to excerpt,
        "ocr_engine" to "mlkit",
        "ocr_is_truncated" to isTruncated,
        "ocr_page_count" to pageCount,
        "ocr_processed_pages" to processedPages,
      )
    } catch (_: Throwable) {
      return null
    } finally {
      try {
        recognizer.close()
      } catch (_: Throwable) {}
      try {
        renderer?.close()
      } catch (_: Throwable) {}
      try {
        descriptor?.close()
      } catch (_: Throwable) {}
      try {
        inputFile?.delete()
      } catch (_: Throwable) {}
    }
  }

  private fun runImageOcrWithMlKit(
    imageBytes: ByteArray,
    languageHints: String,
  ): Map<String, Any>? {
    if (imageBytes.isEmpty()) return null
    val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size) ?: return null
    val recognizer = selectTextRecognizer(languageHints)
    try {
      val text =
        try {
          Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0))).text
        } catch (_: Throwable) {
          ""
        }.trim()
      val fullTruncated = truncateUtf8(text, maxBytes = 256 * 1024)
      val excerpt = truncateUtf8(fullTruncated, maxBytes = 8 * 1024)
      return mapOf(
        "ocr_text_full" to fullTruncated,
        "ocr_text_excerpt" to excerpt,
        "ocr_engine" to "mlkit",
        "ocr_is_truncated" to (fullTruncated != text),
        "ocr_page_count" to 1,
        "ocr_processed_pages" to 1,
      )
    } catch (_: Throwable) {
      return null
    } finally {
      try {
        recognizer.close()
      } catch (_: Throwable) {}
      bitmap.recycle()
    }
  }

  private fun runRenderPdfToLongImage(
    pdfBytes: ByteArray,
    maxPages: Int,
    dpi: Int,
  ): Map<String, Any>? {
    if (pdfBytes.isEmpty()) return null

    var inputFile: File? = null
    var descriptor: ParcelFileDescriptor? = null
    var renderer: PdfRenderer? = null
    var mergedBitmap: Bitmap? = null
    val pageBitmaps = mutableListOf<Bitmap>()

    try {
      inputFile = File.createTempFile("secondloop_pdf_render_", ".pdf", cacheDir)
      inputFile.writeBytes(pdfBytes)

      descriptor = ParcelFileDescriptor.open(inputFile, ParcelFileDescriptor.MODE_READ_ONLY)
      renderer = PdfRenderer(descriptor)
      val pageCount = renderer.pageCount
      if (pageCount <= 0) return null

      val targetPages = pageCount.coerceAtMost(maxPages)
      val maxOutputWidth = 1536
      val maxOutputHeight = 20_000
      val maxOutputPixels = 20_000_000L

      var totalHeight = 0
      var outputWidth = 0
      var processedPages = 0

      for (index in 0 until targetPages) {
        val page = renderer.openPage(index)
        try {
          val scale = (dpi.toFloat() / 72f).coerceIn(1.0f, 6.0f)
          val sourceWidth = (page.width * scale).toInt().coerceAtLeast(1)
          val sourceHeight = (page.height * scale).toInt().coerceAtLeast(1)

          val (width, height) = if (sourceWidth <= maxOutputWidth) {
            sourceWidth to sourceHeight
          } else {
            val ratio = maxOutputWidth.toFloat() / sourceWidth.toFloat()
            val resizedHeight = (sourceHeight * ratio).toInt().coerceAtLeast(1)
            maxOutputWidth to resizedHeight
          }

          val nextTotalHeight = totalHeight + height
          val nextOutputWidth = maxOf(outputWidth, width)
          if (nextTotalHeight > maxOutputHeight) break
          if (nextOutputWidth.toLong() * nextTotalHeight.toLong() > maxOutputPixels) break

          val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
          bitmap.eraseColor(Color.WHITE)
          page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

          pageBitmaps.add(bitmap)
          totalHeight = nextTotalHeight
          outputWidth = nextOutputWidth
          processedPages += 1
        } finally {
          page.close()
        }
      }

      if (pageBitmaps.isEmpty() || outputWidth <= 0 || totalHeight <= 0) {
        return null
      }

      mergedBitmap = Bitmap.createBitmap(outputWidth, totalHeight, Bitmap.Config.ARGB_8888)
      val canvas = Canvas(mergedBitmap)
      canvas.drawColor(Color.WHITE)

      var y = 0f
      for (bitmap in pageBitmaps) {
        canvas.drawBitmap(bitmap, 0f, y, null)
        y += bitmap.height.toFloat()
      }

      val out = ByteArrayOutputStream()
      if (!mergedBitmap.compress(Bitmap.CompressFormat.JPEG, 82, out)) {
        return null
      }
      val imageBytes = out.toByteArray()
      if (imageBytes.isEmpty()) return null

      return mapOf(
        "image_bytes" to imageBytes,
        "image_mime_type" to "image/jpeg",
        "page_count" to pageCount,
        "processed_pages" to processedPages,
      )
    } catch (_: Throwable) {
      return null
    } finally {
      for (bitmap in pageBitmaps) {
        try {
          bitmap.recycle()
        } catch (_: Throwable) {}
      }
      try {
        mergedBitmap?.recycle()
      } catch (_: Throwable) {}
      try {
        renderer?.close()
      } catch (_: Throwable) {}
      try {
        descriptor?.close()
      } catch (_: Throwable) {}
      try {
        inputFile?.delete()
      } catch (_: Throwable) {}
    }
  }

  private fun truncateUtf8(text: String, maxBytes: Int): String {
    val data = text.toByteArray(Charsets.UTF_8)
    if (data.size <= maxBytes) return text
    if (maxBytes <= 0) return ""
    var end = maxBytes
    while (end > 0 && (data[end].toInt() and 0xC0) == 0x80) {
      end -= 1
    }
    if (end <= 0) return ""
    return data.copyOf(end).toString(Charsets.UTF_8)
  }
}

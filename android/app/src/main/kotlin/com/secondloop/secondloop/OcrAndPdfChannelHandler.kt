package com.secondloop.secondloop

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
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
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class OcrAndPdfChannelHandler(
  private val cacheDir: File,
) {
  fun handle(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "ocrPdf" -> handleOcrPdf(call, result)
      "ocrImage" -> handleOcrImage(call, result)
      "compressPdf" -> handleCompressPdf(call, result)
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

  private fun handleCompressPdf(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val bytes = args?.get("bytes") as? ByteArray
    if (bytes == null || bytes.isEmpty()) {
      result.success(null)
      return
    }

    val requestedDpi = normalizePositiveInt(args["scan_dpi"], fallback = 180, upperBound = 600)
    val dpi = requestedDpi.coerceIn(150, 200)
    Thread {
      val payload =
        try {
          runScanPdfCompression(bytes, dpi)
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

  private fun runScanPdfCompression(
    pdfBytes: ByteArray,
    dpi: Int,
  ): ByteArray? {
    if (pdfBytes.isEmpty()) return null

    var inputFile: File? = null
    var outputFile: File? = null
    var descriptor: ParcelFileDescriptor? = null
    var renderer: PdfRenderer? = null
    var outputDocument: PdfDocument? = null

    try {
      inputFile = File.createTempFile("secondloop_pdf_input_", ".pdf", cacheDir)
      inputFile.writeBytes(pdfBytes)
      outputFile = File.createTempFile("secondloop_pdf_output_", ".pdf", cacheDir)

      descriptor = ParcelFileDescriptor.open(inputFile, ParcelFileDescriptor.MODE_READ_ONLY)
      renderer = PdfRenderer(descriptor)
      if (renderer.pageCount <= 0) return null

      outputDocument = PdfDocument()
      val scale = (dpi.toFloat() / 72f).coerceIn(1.0f, 6.0f)

      for (index in 0 until renderer.pageCount) {
        val page = renderer.openPage(index)
        try {
          val targetWidth = (page.width * scale).toInt().coerceAtLeast(1)
          val targetHeight = (page.height * scale).toInt().coerceAtLeast(1)
          val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
          try {
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val pageInfo = PdfDocument.PageInfo.Builder(
              targetWidth,
              targetHeight,
              index + 1,
            ).create()
            val outputPage = outputDocument.startPage(pageInfo)
            outputPage.canvas.drawColor(Color.WHITE)
            outputPage.canvas.drawBitmap(
              bitmap,
              Rect(0, 0, targetWidth, targetHeight),
              Rect(0, 0, targetWidth, targetHeight),
              null,
            )
            outputDocument.finishPage(outputPage)
          } finally {
            bitmap.recycle()
          }
        } finally {
          page.close()
        }
      }

      FileOutputStream(outputFile).use { stream ->
        outputDocument.writeTo(stream)
      }
      val compressed = outputFile.readBytes()
      if (compressed.isEmpty()) return null
      return compressed
    } catch (_: Throwable) {
      return null
    } finally {
      try {
        outputDocument?.close()
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
      try {
        outputFile?.delete()
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

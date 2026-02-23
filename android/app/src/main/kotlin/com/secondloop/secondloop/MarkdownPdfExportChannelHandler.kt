package com.secondloop.secondloop

import android.app.Activity
import android.graphics.pdf.PdfDocument
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

class MarkdownPdfExportChannelHandler(
  private val activity: Activity,
  private val cacheDir: File,
) {
  private val mainHandler = Handler(Looper.getMainLooper())

  fun handle(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "exportMarkdownHtmlToPdf" -> handleExport(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleExport(call: MethodCall, result: MethodChannel.Result) {
    val arguments = call.arguments as? Map<*, *>
    val html = (arguments?.get("html") as? String)?.trim()
    if (html.isNullOrEmpty()) {
      result.error(
        "markdown_pdf_export_invalid_args",
        "Missing non-empty html argument",
        null,
      )
      return
    }

    mainHandler.post {
      exportHtmlToPdf(html, result)
    }
  }

  private fun exportHtmlToPdf(html: String, result: MethodChannel.Result) {
    val completed = AtomicBoolean(false)
    val cleanupActions = mutableListOf<() -> Unit>()

    fun finishWithError(code: String, message: String) {
      if (!completed.compareAndSet(false, true)) {
        return
      }

      cleanupActions.asReversed().forEach { action ->
        runCatching { action.invoke() }
      }
      result.error(code, message, null)
    }

    fun finishWithBytes(bytes: ByteArray) {
      if (!completed.compareAndSet(false, true)) {
        return
      }

      cleanupActions.asReversed().forEach { action ->
        runCatching { action.invoke() }
      }
      result.success(bytes)
    }

    val timeoutRunnable = Runnable {
      finishWithError(
        "markdown_pdf_export_timeout",
        "HTML to PDF export timed out",
      )
    }
    mainHandler.postDelayed(timeoutRunnable, 45_000)
    cleanupActions.add {
      mainHandler.removeCallbacks(timeoutRunnable)
    }

    val webView = WebView(activity)
    cleanupActions.add {
      runCatching {
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.destroy()
      }
    }

    val rootView = activity.window?.decorView as? FrameLayout
    rootView?.addView(
      webView,
      FrameLayout.LayoutParams(1, 1),
    )
    cleanupActions.add {
      runCatching {
        rootView?.removeView(webView)
      }
    }

    webView.settings.javaScriptEnabled = true
    webView.settings.domStorageEnabled = true
    webView.settings.loadsImagesAutomatically = true
    webView.settings.allowContentAccess = false
    webView.settings.allowFileAccess = false

    webView.webViewClient = object : WebViewClient() {
      override fun onReceivedError(
        view: WebView,
        request: WebResourceRequest,
        error: WebResourceError,
      ) {
        super.onReceivedError(view, request, error)
        if (!request.isForMainFrame) {
          return
        }

        val reason = error.description?.toString() ?: "main_frame_load_error"
        finishWithError("markdown_pdf_export_webview_error", reason)
      }

      @Deprecated("Deprecated in Java")
      override fun onReceivedError(
        view: WebView,
        errorCode: Int,
        description: String?,
        failingUrl: String?,
      ) {
        super.onReceivedError(view, errorCode, description, failingUrl)
        val reason = description ?: "legacy_main_frame_load_error"
        finishWithError("markdown_pdf_export_webview_error", reason)
      }

      override fun onPageFinished(view: WebView, url: String?) {
        super.onPageFinished(view, url)
        waitForPageReady(
          webView = view,
          completed = completed,
          onReady = {
            writePdfFromWebView(
              webView = view,
              finishWithError = ::finishWithError,
              finishWithBytes = ::finishWithBytes,
            )
          },
          onError = { message ->
            finishWithError(
              "markdown_pdf_export_js_probe_failed",
              message,
            )
          },
        )
      }
    }

    webView.loadDataWithBaseURL(
      "https://secondloop.local/",
      html,
      "text/html",
      "utf-8",
      null,
    )
  }

  private fun waitForPageReady(
    webView: WebView,
    completed: AtomicBoolean,
    onReady: () -> Unit,
    onError: (String) -> Unit,
    attempt: Int = 0,
  ) {
    if (completed.get()) {
      return
    }

    if (attempt > 240) {
      onReady()
      return
    }

    val probeScript =
      "(function(){return window.__SECONDLOOP_PDF_READY__ === true ? 'true' : 'false';})();"

    runCatching {
      webView.evaluateJavascript(probeScript) { value ->
        if (completed.get()) {
          return@evaluateJavascript
        }

        val ready = value == "true" || value == "\"true\""
        if (ready) {
          onReady()
          return@evaluateJavascript
        }

        mainHandler.postDelayed(
          {
            waitForPageReady(
              webView = webView,
              completed = completed,
              onReady = onReady,
              onError = onError,
              attempt = attempt + 1,
            )
          },
          35,
        )
      }
    }.onFailure { error ->
      onError(error.message ?: "evaluateJavascript_failed")
    }
  }

  private fun writePdfFromWebView(
    webView: WebView,
    finishWithError: (String, String) -> Unit,
    finishWithBytes: (ByteArray) -> Unit,
  ) {
    val pageWidthPx = 595
    val pageHeightPx = 842
    val density = activity.resources.displayMetrics.density
    val measuredContentHeightPx = (webView.contentHeight * density).roundToInt()
    val contentHeightPx = max(measuredContentHeightPx, pageHeightPx)

    webView.measure(
      View.MeasureSpec.makeMeasureSpec(pageWidthPx, View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(contentHeightPx, View.MeasureSpec.EXACTLY),
    )
    webView.layout(0, 0, pageWidthPx, contentHeightPx)

    val pageCount = max(1, ceil(contentHeightPx.toDouble() / pageHeightPx.toDouble()).toInt())

    val pdfResult = runCatching {
      val document = PdfDocument()
      try {
        for (pageIndex in 0 until pageCount) {
          val pageInfo = PdfDocument.PageInfo.Builder(pageWidthPx, pageHeightPx, pageIndex + 1)
            .create()
          val page = document.startPage(pageInfo)
          val canvas = page.canvas

          canvas.save()
          canvas.translate(0f, -(pageIndex * pageHeightPx).toFloat())
          webView.draw(canvas)
          canvas.restore()

          document.finishPage(page)
        }

        ByteArrayOutputStream().use { output ->
          document.writeTo(output)
          output.toByteArray()
        }
      } finally {
        document.close()
      }
    }

    val bytes = pdfResult.getOrNull()
    if (bytes == null || bytes.isEmpty()) {
      finishWithError(
        "markdown_pdf_export_io_failed",
        pdfResult.exceptionOrNull()?.message ?: "Generated PDF is empty",
      )
      return
    }

    finishWithBytes(bytes)
  }
}

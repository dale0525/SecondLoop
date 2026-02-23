package com.secondloop.secondloop

import android.app.Activity
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

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
    val adapter = webView.createPrintDocumentAdapter("secondloop_markdown_pdf")
    val attributes = PrintAttributes.Builder()
      .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
      .setResolution(PrintAttributes.Resolution("secondloop_pdf", "secondloop_pdf", 600, 600))
      .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
      .build()

    adapter.onStart()
    adapter.onLayout(
      null,
      attributes,
      CancellationSignal(),
      object : PrintDocumentAdapter.LayoutResultCallback() {
        override fun onLayoutFinished(info: android.print.PrintDocumentInfo, changed: Boolean) {
          super.onLayoutFinished(info, changed)
          writePdfContent(
            adapter = adapter,
            finishWithError = finishWithError,
            finishWithBytes = finishWithBytes,
          )
        }

        override fun onLayoutFailed(error: CharSequence?) {
          super.onLayoutFailed(error)
          finishWithError(
            "markdown_pdf_export_layout_failed",
            error?.toString() ?: "Print layout failed",
          )
        }

        override fun onLayoutCancelled() {
          super.onLayoutCancelled()
          finishWithError(
            "markdown_pdf_export_layout_cancelled",
            "Print layout cancelled",
          )
        }
      },
      Bundle(),
    )
  }

  private fun writePdfContent(
    adapter: PrintDocumentAdapter,
    finishWithError: (String, String) -> Unit,
    finishWithBytes: (ByteArray) -> Unit,
  ) {
    val outputFile = runCatching {
      File.createTempFile("secondloop_markdown_", ".pdf", cacheDir)
    }.getOrNull() ?: run {
      finishWithError(
        "markdown_pdf_export_io_failed",
        "Failed to allocate temporary PDF file",
      )
      return
    }

    val descriptor = runCatching {
      ParcelFileDescriptor.open(
        outputFile,
        ParcelFileDescriptor.MODE_CREATE or
          ParcelFileDescriptor.MODE_TRUNCATE or
          ParcelFileDescriptor.MODE_READ_WRITE,
      )
    }.getOrNull() ?: run {
      outputFile.delete()
      finishWithError(
        "markdown_pdf_export_io_failed",
        "Failed to open temporary PDF descriptor",
      )
      return
    }

    adapter.onWrite(
      arrayOf(PageRange.ALL_PAGES),
      descriptor,
      CancellationSignal(),
      object : PrintDocumentAdapter.WriteResultCallback() {
        override fun onWriteFinished(pages: Array<PageRange>) {
          super.onWriteFinished(pages)
          descriptor.close()

          val bytes = runCatching {
            outputFile.readBytes()
          }.getOrNull()

          outputFile.delete()
          adapter.onFinish()

          if (bytes == null || bytes.isEmpty()) {
            finishWithError(
              "markdown_pdf_export_io_failed",
              "Generated PDF is empty",
            )
            return
          }

          finishWithBytes(bytes)
        }

        override fun onWriteFailed(error: CharSequence?) {
          super.onWriteFailed(error)
          descriptor.close()
          outputFile.delete()
          adapter.onFinish()
          finishWithError(
            "markdown_pdf_export_write_failed",
            error?.toString() ?: "PDF write failed",
          )
        }

        override fun onWriteCancelled() {
          super.onWriteCancelled()
          descriptor.close()
          outputFile.delete()
          adapter.onFinish()
          finishWithError(
            "markdown_pdf_export_write_cancelled",
            "PDF write cancelled",
          )
        }
      },
    )
  }
}

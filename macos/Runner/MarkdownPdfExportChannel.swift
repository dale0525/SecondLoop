import Cocoa
import FlutterMacOS
import WebKit

private let kMarkdownPdfMethod = "exportMarkdownHtmlToPdf"
private let kMarkdownPdfPageWidth: CGFloat = 595.2
private let kMarkdownPdfPageHeight: CGFloat = 841.8

final class MarkdownPdfExportChannel {
  private let channel: FlutterMethodChannel
  private var activeTasks: [UUID: MarkdownPdfExportTask] = [:]

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "secondloop/markdown_pdf_export",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == kMarkdownPdfMethod else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let args = call.arguments as? [String: Any],
          let html = args["html"] as? String,
          !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(
        FlutterError(
          code: "markdown_pdf_export_invalid_args",
          message: "Missing non-empty html argument",
          details: nil
        )
      )
      return
    }

    let task = MarkdownPdfExportTask(html: html) { [weak self] id in
      self?.activeTasks.removeValue(forKey: id)
    }
    activeTasks[task.id] = task
    task.start(result: result)
  }
}

private final class MarkdownPdfExportTask: NSObject, WKNavigationDelegate {
  let id = UUID()

  private let html: String
  private let onFinished: (UUID) -> Void

  private var result: FlutterResult?
  private var timeoutWorkItem: DispatchWorkItem?
  private var webView: WKWebView?

  init(
    html: String,
    onFinished: @escaping (UUID) -> Void
  ) {
    self.html = html
    self.onFinished = onFinished
    super.init()
  }

  func start(result: @escaping FlutterResult) {
    self.result = result

    let config = WKWebViewConfiguration()
    config.preferences.javaScriptEnabled = true
    if #available(macOS 11.0, *) {
      config.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    let webView = WKWebView(
      frame: NSRect(x: 0, y: 0, width: kMarkdownPdfPageWidth, height: kMarkdownPdfPageHeight),
      configuration: config
    )
    webView.navigationDelegate = self
    self.webView = webView

    let timeout = DispatchWorkItem { [weak self] in
      self?.complete(
        failure: FlutterError(
          code: "markdown_pdf_export_timeout",
          message: "Markdown PDF export timed out",
          details: nil
        )
      )
    }
    timeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)

    webView.loadHTMLString(html, baseURL: URL(string: "https://secondloop.local/"))
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    waitForRenderReady(attempt: 0)
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    complete(
      failure: FlutterError(
        code: "markdown_pdf_export_navigation_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    complete(
      failure: FlutterError(
        code: "markdown_pdf_export_navigation_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
  }

  private func waitForRenderReady(attempt: Int) {
    guard let webView = webView else {
      complete(
        failure: FlutterError(
          code: "markdown_pdf_export_missing_webview",
          message: "Web view is unavailable",
          details: nil
        )
      )
      return
    }

    if attempt > 240 {
      exportPdf()
      return
    }

    webView.evaluateJavaScript("window.__SECONDLOOP_PDF_READY__ === true") { [weak self] value, error in
      guard let self = self else { return }

      if let error = error {
        self.complete(
          failure: FlutterError(
            code: "markdown_pdf_export_js_probe_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
        return
      }

      let isReady: Bool
      if let boolValue = value as? Bool {
        isReady = boolValue
      } else if let stringValue = value as? String {
        isReady = stringValue == "true"
      } else {
        isReady = false
      }

      if isReady {
        self.exportPdf()
        return
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
        self?.waitForRenderReady(attempt: attempt + 1)
      }
    }
  }

  private func exportPdf() {
    guard let webView = webView else {
      complete(
        failure: FlutterError(
          code: "markdown_pdf_export_missing_webview",
          message: "Web view is unavailable",
          details: nil
        )
      )
      return
    }

    webView.evaluateJavaScript(
      "Math.max(document.documentElement.scrollHeight || 0, document.body.scrollHeight || 0, 1123)"
    ) { [weak self] value, _ in
      guard let self = self else { return }

      var contentHeight = kMarkdownPdfPageHeight
      if let number = value as? NSNumber {
        contentHeight = CGFloat(truncating: number)
      } else if let raw = value as? String,
                let parsed = Double(raw.replacingOccurrences(of: "\"", with: "")) {
        contentHeight = CGFloat(parsed)
      }

      contentHeight = max(contentHeight, kMarkdownPdfPageHeight)
      webView.frame = NSRect(x: 0, y: 0, width: kMarkdownPdfPageWidth, height: contentHeight)

      let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("secondloop_markdown_\(UUID().uuidString).pdf")

      let printInfo = NSPrintInfo()
      printInfo.paperSize = NSSize(width: kMarkdownPdfPageWidth, height: kMarkdownPdfPageHeight)
      printInfo.topMargin = 0
      printInfo.bottomMargin = 0
      printInfo.leftMargin = 0
      printInfo.rightMargin = 0
      printInfo.horizontalPagination = .automatic
      printInfo.verticalPagination = .automatic
      printInfo.isVerticallyCentered = false
      printInfo.isHorizontallyCentered = false
      printInfo.jobDisposition = .save
      printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outputUrl

      let operation = NSPrintOperation(view: webView, printInfo: printInfo)
      operation.showsPrintPanel = false
      operation.showsProgressPanel = false
      _ = operation.run()

      guard let data = try? Data(contentsOf: outputUrl), !data.isEmpty else {
        let fallback = webView.dataWithPDF(inside: webView.bounds)
        if fallback.isEmpty {
          self.complete(
            failure: FlutterError(
              code: "markdown_pdf_export_io_failed",
              message: "Failed to generate PDF bytes",
              details: nil
            )
          )
          return
        }

        self.complete(success: fallback)
        return
      }

      try? FileManager.default.removeItem(at: outputUrl)
      self.complete(success: data)
    }
  }

  private func complete(success data: Data) {
    guard let result = result else {
      return
    }

    result(FlutterStandardTypedData(bytes: data))
    finish()
  }

  private func complete(failure error: FlutterError) {
    guard let result = result else {
      return
    }

    result(error)
    finish()
  }

  private func finish() {
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil

    webView?.navigationDelegate = nil
    webView = nil

    result = nil
    onFinished(id)
  }
}

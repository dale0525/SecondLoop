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
      frame: NSRect(
        x: 0,
        y: 0,
        width: kMarkdownPdfPageWidth,
        height: kMarkdownPdfPageHeight
      ),
      configuration: config
    )
    webView.navigationDelegate = self
    webView.alphaValue = 0.01
    self.webView = webView

    if let hostView = MarkdownPdfExportTask.resolveHostView() {
      hostView.addSubview(webView)
    }

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

    exportPdfViaPrintOperation(webView: webView)
  }

  private func exportPdfViaPrintOperation(webView: WKWebView) {
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

    let operation: NSPrintOperation
    if #available(macOS 11.0, *) {
      operation = webView.printOperation(with: printInfo)
    } else {
      operation = NSPrintOperation(view: webView, printInfo: printInfo)
    }

    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    operation.canSpawnSeparateThread = true

    let didRun = operation.run()
    if didRun,
       let data = waitForPdfFileData(at: outputUrl) {
      try? FileManager.default.removeItem(at: outputUrl)
      complete(success: data)
      return
    }

    try? FileManager.default.removeItem(at: outputUrl)
    complete(
      failure: FlutterError(
        code: "markdown_pdf_export_io_failed",
        message: "Failed to generate PDF bytes",
        details: nil
      )
    )
  }

  private func waitForPdfFileData(at outputUrl: URL) -> Data? {
    let maxAttempts = 20
    for attempt in 0 ... maxAttempts {
      if let data = try? Data(contentsOf: outputUrl), !data.isEmpty {
        return data
      }

      if attempt < maxAttempts {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
    }

    return nil
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

  private static func resolveHostView() -> NSView? {
    if let keyWindow = NSApplication.shared.windows.first(where: { $0.isKeyWindow }),
       let contentView = keyWindow.contentView {
      return contentView
    }

    if let mainContentView = NSApplication.shared.mainWindow?.contentView {
      return mainContentView
    }

    return NSApplication.shared.windows.first?.contentView
  }

  private func finish() {
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil

    webView?.navigationDelegate = nil
    webView?.removeFromSuperview()
    webView = nil

    result = nil
    onFinished(id)
  }
}

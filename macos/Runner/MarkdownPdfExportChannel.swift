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

    let task = MarkdownPdfExportTask(
      html: html,
      pageBackgroundColorHex: args["pageBackgroundColorHex"] as? String
    ) { [weak self] id in
      self?.activeTasks.removeValue(forKey: id)
    }
    activeTasks[task.id] = task
    task.start(result: result)
  }
}

private final class MarkdownPdfExportTask: NSObject, WKNavigationDelegate {
  let id = UUID()

  private let html: String
  private let pageBackgroundColorHex: String?
  private let onFinished: (UUID) -> Void

  private var result: FlutterResult?
  private var timeoutWorkItem: DispatchWorkItem?
  private var webView: WKWebView?
  private var pendingPrintOperation: NSPrintOperation?
  private var pendingPdfOutputUrl: URL?

  init(
    html: String,
    pageBackgroundColorHex: String?,
    onFinished: @escaping (UUID) -> Void
  ) {
    self.html = html
    self.pageBackgroundColorHex = pageBackgroundColorHex
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

    pendingPrintOperation = operation
    pendingPdfOutputUrl = outputUrl

    if let hostWindow = MarkdownPdfExportTask.resolveHostWindow() {
      operation.runModal(
        for: hostWindow,
        delegate: self,
        didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
        contextInfo: nil
      )
      return
    }

    let didRun = operation.run()
    finalizePrintOperation(success: didRun)
  }

  @objc
  private func printOperationDidRun(
    _ operation: NSPrintOperation,
    success: Bool,
    contextInfo: UnsafeMutableRawPointer?
  ) {
    finalizePrintOperation(success: success, completedOperation: operation)
  }

  private func finalizePrintOperation(
    success: Bool,
    completedOperation: NSPrintOperation? = nil
  ) {
    if let completedOperation,
       let pendingPrintOperation,
       completedOperation !== pendingPrintOperation {
      return
    }

    let outputUrl = pendingPdfOutputUrl
    pendingPrintOperation = nil
    pendingPdfOutputUrl = nil

    guard success else {
      if let outputUrl {
        try? FileManager.default.removeItem(at: outputUrl)
      }
      complete(
        failure: FlutterError(
          code: "markdown_pdf_export_io_failed",
          message: "Failed to generate PDF bytes",
          details: nil
        )
      )
      return
    }

    guard let outputUrl else {
      complete(
        failure: FlutterError(
          code: "markdown_pdf_export_io_failed",
          message: "Missing PDF output path",
          details: nil
        )
      )
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let data = try? Data(contentsOf: outputUrl)
      try? FileManager.default.removeItem(at: outputUrl)

      DispatchQueue.main.async {
        guard let self = self else { return }

        guard let data, !data.isEmpty else {
          self.complete(
            failure: FlutterError(
              code: "markdown_pdf_export_io_failed",
              message: "Generated PDF is empty",
              details: nil
            )
          )
          return
        }

        self.complete(success: self.applyPageBackgroundIfNeeded(pdfData: data))
      }
    }
  }


  private func applyPageBackgroundIfNeeded(pdfData: Data) -> Data {
    guard let pageBackgroundColor = parsePageBackgroundColor() else {
      return pdfData
    }

    guard let provider = CGDataProvider(data: pdfData as CFData),
          let sourceDocument = CGPDFDocument(provider),
          sourceDocument.numberOfPages > 0 else {
      return pdfData
    }

    let outputData = NSMutableData()
    guard let consumer = CGDataConsumer(data: outputData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
      return pdfData
    }

    for pageIndex in 1 ... sourceDocument.numberOfPages {
      guard let page = sourceDocument.page(at: pageIndex) else {
        continue
      }

      let sourceBox = page.getBoxRect(.mediaBox)
      let pageRect = CGRect(origin: .zero, size: sourceBox.size)

      context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)

      context.saveGState()
      context.setBlendMode(.normal)
      context.setFillColor(pageBackgroundColor.cgColor)
      context.fill(pageRect)
      context.restoreGState()

      context.saveGState()
      context.setBlendMode(.normal)
      let drawingTransform = page.getDrawingTransform(
        .mediaBox,
        rect: pageRect,
        rotate: 0,
        preserveAspectRatio: true
      )
      context.concatenate(drawingTransform)
      context.drawPDFPage(page)
      context.restoreGState()

      context.endPDFPage()
    }

    context.closePDF()
    let rebuilt = outputData as Data
    return rebuilt.isEmpty ? pdfData : rebuilt
  }

  private func parsePageBackgroundColor() -> NSColor? {
    guard let rawValue = pageBackgroundColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawValue.isEmpty else {
      return nil
    }

    let normalized = rawValue.hasPrefix("#") ? String(rawValue.dropFirst()) : rawValue
    if normalized.count != 6 && normalized.count != 8 {
      return nil
    }

    guard let value = UInt32(normalized, radix: 16) else {
      return nil
    }

    if normalized.count == 6 {
      let red = CGFloat((value >> 16) & 0xff) / 255.0
      let green = CGFloat((value >> 8) & 0xff) / 255.0
      let blue = CGFloat(value & 0xff) / 255.0
      return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    let alpha = CGFloat((value >> 24) & 0xff) / 255.0
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0
    return NSColor(red: red, green: green, blue: blue, alpha: alpha)
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

  private static func resolveHostWindow() -> NSWindow? {
    if let keyWindow = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
      return keyWindow
    }

    if let mainWindow = NSApplication.shared.mainWindow {
      return mainWindow
    }

    return NSApplication.shared.windows.first
  }

  private static func resolveHostView() -> NSView? {
    resolveHostWindow()?.contentView
  }

  private func finish() {
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil

    if let outputUrl = pendingPdfOutputUrl {
      try? FileManager.default.removeItem(at: outputUrl)
    }
    pendingPrintOperation = nil
    pendingPdfOutputUrl = nil

    webView?.navigationDelegate = nil
    webView?.removeFromSuperview()
    webView = nil

    result = nil
    onFinished(id)
  }
}

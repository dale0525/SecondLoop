import Cocoa
import FlutterMacOS
import WebKit

private let kMarkdownPdfMethod = "exportMarkdownHtmlToPdf"
private let kMarkdownPdfPageWidth: CGFloat = 595.2
private let kMarkdownPdfPageHeight: CGFloat = 841.8
private let kMarkdownPdfTopMargin: CGFloat = 48
private let kMarkdownPdfBottomMargin: CGFloat = 64
private let kMarkdownPdfHorizontalMargin: CGFloat = 54

private struct PdfDetectedMargins {
  let top: CGFloat
  let bottom: CGFloat
  let left: CGFloat
  let right: CGFloat

  static let zero = PdfDetectedMargins(top: 0, bottom: 0, left: 0, right: 0)
}

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
    printInfo.topMargin = kMarkdownPdfTopMargin
    printInfo.bottomMargin = kMarkdownPdfBottomMargin
    printInfo.leftMargin = kMarkdownPdfHorizontalMargin
    printInfo.rightMargin = kMarkdownPdfHorizontalMargin
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
      guard let self = self else { return }

      let data = try? Data(contentsOf: outputUrl)
      try? FileManager.default.removeItem(at: outputUrl)

      guard let data, !data.isEmpty else {
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.complete(
            failure: FlutterError(
              code: "markdown_pdf_export_io_failed",
              message: "Generated PDF is empty",
              details: nil
            )
          )
        }
        return
      }

      let rebuiltData = self.applyPageBackgroundIfNeeded(pdfData: data)
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.complete(success: rebuiltData)
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

      var mediaBox = page.getBoxRect(.mediaBox)
      if mediaBox.width <= 0 || mediaBox.height <= 0 {
        mediaBox = CGRect(
          x: 0,
          y: 0,
          width: kMarkdownPdfPageWidth,
          height: kMarkdownPdfPageHeight
        )
      }

      context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)

      context.saveGState()
      context.setBlendMode(.normal)
      context.setFillColor(pageBackgroundColor.cgColor)
      context.fill(mediaBox)
      context.restoreGState()

      context.saveGState()
      context.setBlendMode(.normal)
      let drawingTransform = page.getDrawingTransform(
        .mediaBox,
        rect: mediaBox,
        rotate: 0,
        preserveAspectRatio: false
      )
      context.concatenate(drawingTransform)
      context.drawPDFPage(page)
      context.restoreGState()

      let detectedMargins = detectWhitePageMargins(page: page, mediaBox: mediaBox)

      context.saveGState()
      context.setBlendMode(.normal)
      context.setFillColor(pageBackgroundColor.cgColor)
      fillPageMargins(
        context: context,
        mediaBox: mediaBox,
        margins: detectedMargins
      )
      context.restoreGState()

      context.endPDFPage()
    }

    context.closePDF()
    let rebuilt = outputData as Data
    return rebuilt.isEmpty ? pdfData : rebuilt
  }

  private func fillPageMargins(
    context: CGContext,
    mediaBox: CGRect,
    margins: PdfDetectedMargins
  ) {
    if margins.top <= 0 && margins.bottom <= 0 && margins.left <= 0 && margins.right <= 0 {
      return
    }

    let pageWidth = max(mediaBox.width, 1)
    let pageHeight = max(mediaBox.height, 1)

    let leftMargin = max(0, min(pageWidth * 0.48, margins.left))
    let rightMargin = max(0, min(pageWidth * 0.48, margins.right))
    let topMargin = max(0, min(pageHeight * 0.48, margins.top))
    let bottomMargin = max(0, min(pageHeight * 0.48, margins.bottom))

    if topMargin > 0 {
      context.fill(
        CGRect(
          x: mediaBox.minX,
          y: mediaBox.maxY - topMargin,
          width: pageWidth,
          height: topMargin
        )
      )
    }

    if bottomMargin > 0 {
      context.fill(
        CGRect(
          x: mediaBox.minX,
          y: mediaBox.minY,
          width: pageWidth,
          height: bottomMargin
        )
      )
    }

    if leftMargin > 0 {
      context.fill(
        CGRect(
          x: mediaBox.minX,
          y: mediaBox.minY,
          width: leftMargin,
          height: pageHeight
        )
      )
    }

    if rightMargin > 0 {
      context.fill(
        CGRect(
          x: mediaBox.maxX - rightMargin,
          y: mediaBox.minY,
          width: rightMargin,
          height: pageHeight
        )
      )
    }
  }

  private func detectWhitePageMargins(page: CGPDFPage, mediaBox: CGRect) -> PdfDetectedMargins {
    let sampleWidth = 240
    let sampleHeight = 340
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let baseAddress = buffer.baseAddress,
            let bitmapContext = CGContext(
              data: baseAddress,
              width: sampleWidth,
              height: sampleHeight,
              bitsPerComponent: 8,
              bytesPerRow: sampleWidth * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
        return false
      }

      let bounds = CGRect(
        x: 0,
        y: 0,
        width: CGFloat(sampleWidth),
        height: CGFloat(sampleHeight)
      )
      bitmapContext.setFillColor(NSColor.white.cgColor)
      bitmapContext.fill(bounds)
      let transform = page.getDrawingTransform(
        .mediaBox,
        rect: bounds,
        rotate: 0,
        preserveAspectRatio: false
      )
      bitmapContext.concatenate(transform)
      bitmapContext.drawPDFPage(page)
      return true
    }

    guard rendered else {
      return .zero
    }

    let maxNonWhiteInColumn = max(1, Int(Double(sampleHeight) * 0.012))
    let maxNonWhiteInRow = max(1, Int(Double(sampleWidth) * 0.012))

    func isNearWhitePixel(x: Int, y: Int) -> Bool {
      let index = (y * sampleWidth + x) * 4
      let red = pixels[index]
      let green = pixels[index + 1]
      let blue = pixels[index + 2]
      return red >= 246 && green >= 246 && blue >= 246
    }

    func isMostlyWhiteColumn(_ x: Int) -> Bool {
      var nonWhite = 0
      for y in 0 ..< sampleHeight {
        if !isNearWhitePixel(x: x, y: y) {
          nonWhite += 1
          if nonWhite > maxNonWhiteInColumn {
            return false
          }
        }
      }
      return true
    }

    func isMostlyWhiteRow(_ y: Int) -> Bool {
      var nonWhite = 0
      for x in 0 ..< sampleWidth {
        if !isNearWhitePixel(x: x, y: y) {
          nonWhite += 1
          if nonWhite > maxNonWhiteInRow {
            return false
          }
        }
      }
      return true
    }

    var leftColumns = 0
    while leftColumns < sampleWidth / 2 && isMostlyWhiteColumn(leftColumns) {
      leftColumns += 1
    }

    var rightColumns = 0
    while rightColumns < sampleWidth / 2 && isMostlyWhiteColumn(sampleWidth - rightColumns - 1) {
      rightColumns += 1
    }

    var topRows = 0
    while topRows < sampleHeight / 2 && isMostlyWhiteRow(sampleHeight - topRows - 1) {
      topRows += 1
    }

    var bottomRows = 0
    while bottomRows < sampleHeight / 2 && isMostlyWhiteRow(bottomRows) {
      bottomRows += 1
    }

    let widthScale = mediaBox.width / CGFloat(sampleWidth)
    let heightScale = mediaBox.height / CGFloat(sampleHeight)

    func convertMargin(_ value: Int, scale: CGFloat) -> CGFloat {
      let points = CGFloat(value) * scale
      if points < 0.6 {
        return 0
      }
      return points
    }

    return PdfDetectedMargins(
      top: convertMargin(topRows, scale: heightScale),
      bottom: convertMargin(bottomRows, scale: heightScale),
      left: convertMargin(leftColumns, scale: widthScale),
      right: convertMargin(rightColumns, scale: widthScale)
    )
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

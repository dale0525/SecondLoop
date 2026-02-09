import Cocoa
import FlutterMacOS
import AVFoundation
import PDFKit
import Vision

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }

    let audioTranscodeChannel = FlutterMethodChannel(
      name: "secondloop/audio_transcode",
      binaryMessenger: controller.engine.binaryMessenger
    )
    audioTranscodeChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }

      switch call.method {
      case "transcodeToM4a":
        self.handleTranscodeToM4a(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let ocrChannel = FlutterMethodChannel(
      name: "secondloop/ocr",
      binaryMessenger: controller.engine.binaryMessenger
    )
    ocrChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }

      switch call.method {
      case "ocrPdf":
        self.handleOcrPdf(call: call, result: result)
      case "ocrImage":
        self.handleOcrImage(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  private func handleTranscodeToM4a(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let inputPathRaw = args["input_path"] as? String,
          let outputPathRaw = args["output_path"] as? String else {
      result(false)
      return
    }

    let inputPath = inputPathRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    let outputPath = outputPathRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    if inputPath.isEmpty || outputPath.isEmpty {
      result(false)
      return
    }

    let sampleRateHz = args["sample_rate_hz"] as? Int ?? 24000
    let bitrateKbps = args["bitrate_kbps"] as? Int ?? 48
    let mono = args["mono"] as? Bool ?? true

    transcodeToM4a(
      inputPath: inputPath,
      outputPath: outputPath,
      sampleRateHz: sampleRateHz,
      bitrateKbps: bitrateKbps,
      mono: mono
    ) { ok in
      result(ok)
    }
  }

  private func transcodeToM4a(
    inputPath: String,
    outputPath: String,
    sampleRateHz: Int,
    bitrateKbps: Int,
    mono: Bool,
    completion: @escaping (Bool) -> Void
  ) {
    let inputUrl = URL(fileURLWithPath: inputPath)
    let outputUrl = URL(fileURLWithPath: outputPath)
    let outputDir = outputUrl.deletingLastPathComponent()

    do {
      try FileManager.default.createDirectory(
        at: outputDir,
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: outputPath) {
        try FileManager.default.removeItem(at: outputUrl)
      }
    } catch {
      completion(false)
      return
    }

    let asset = AVAsset(url: inputUrl)
    guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
      completion(false)
      return
    }

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      completion(false)
      return
    }

    let readerOutput = AVAssetReaderTrackOutput(
      track: audioTrack,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
      ]
    )
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else {
      completion(false)
      return
    }
    reader.add(readerOutput)

    let channelCount = mono ? 1 : 2
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(url: outputUrl, fileType: .m4a)
    } catch {
      completion(false)
      return
    }

    let writerInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: max(8000, sampleRateHz),
        AVEncoderBitRateKey: max(16, bitrateKbps) * 1000,
        AVNumberOfChannelsKey: channelCount,
      ]
    )
    writerInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(writerInput) else {
      completion(false)
      return
    }
    writer.add(writerInput)

    guard reader.startReading() else {
      completion(false)
      return
    }
    guard writer.startWriting() else {
      completion(false)
      return
    }
    writer.startSession(atSourceTime: .zero)

    let queue = DispatchQueue(label: "secondloop.audio_transcode.macos")
    writerInput.requestMediaDataWhenReady(on: queue) {
      while writerInput.isReadyForMoreMediaData {
        if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
          if !writerInput.append(sampleBuffer) {
            reader.cancelReading()
            writerInput.markAsFinished()
            writer.cancelWriting()
            DispatchQueue.main.async {
              completion(false)
            }
            return
          }
        } else {
          writerInput.markAsFinished()
          writer.finishWriting {
            let ok = reader.status == .completed &&
              writer.status == .completed &&
              FileManager.default.fileExists(atPath: outputPath)
            DispatchQueue.main.async {
              completion(ok)
            }
          }
          return
        }
      }
    }
  }

  private func handleOcrPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(macOS 10.15, *) else {
      result(nil)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let typed = args["bytes"] as? FlutterStandardTypedData else {
      result(nil)
      return
    }
    let maxPages = normalizePositiveInt(args["max_pages"], fallback: 200, upperBound: 10_000)
    let dpi = normalizePositiveInt(args["dpi"], fallback: 180, upperBound: 600)
    let languageHints = (args["language_hints"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "device_plus_en"

    DispatchQueue.global(qos: .userInitiated).async {
      let payload = self.runPdfOcrWithVision(
        pdfData: typed.data,
        maxPages: maxPages,
        languageHints: languageHints,
        dpi: dpi
      )
      DispatchQueue.main.async {
        result(payload)
      }
    }
  }

  private func handleOcrImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(macOS 10.15, *) else {
      result(nil)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let typed = args["bytes"] as? FlutterStandardTypedData else {
      result(nil)
      return
    }
    let languageHints = (args["language_hints"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "device_plus_en"

    DispatchQueue.global(qos: .userInitiated).async {
      let payload = self.runImageOcrWithVision(
        imageData: typed.data,
        languageHints: languageHints
      )
      DispatchQueue.main.async {
        result(payload)
      }
    }
  }

  private func normalizePositiveInt(_ raw: Any?, fallback: Int, upperBound: Int) -> Int {
    let value: Int
    switch raw {
    case let v as Int:
      value = v
    case let v as NSNumber:
      value = v.intValue
    case let v as String:
      value = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
    default:
      value = fallback
    }
    return max(1, min(upperBound, value))
  }

  @available(macOS 10.15, *)
  private func runPdfOcrWithVision(
    pdfData: Data,
    maxPages: Int,
    languageHints: String,
    dpi: Int
  ) -> [String: Any]? {
    guard let document = PDFDocument(data: pdfData) else {
      return nil
    }
    let pageCount = document.pageCount
    if pageCount <= 0 {
      return nil
    }

    let targetPages = min(pageCount, maxPages)
    var parts = [String]()
    var processedPages = 0
    let recognitionLanguages = visionRecognitionLanguages(from: languageHints)
    let useLanguageCorrection = visionUsesLanguageCorrection(from: languageHints)

    for index in 0..<targetPages {
      guard let page = document.page(at: index),
            let rawImage = renderPdfPageAsCgImage(page: page, dpi: dpi),
            let image = preparedVisionImage(
              from: rawImage,
              languageHints: languageHints
            ) else {
        continue
      }
      do {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = useLanguageCorrection
        if !recognitionLanguages.isEmpty {
          request.recognitionLanguages = recognitionLanguages
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = recognizedLines(from: observations)
        let pageText = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        processedPages += 1
        if !pageText.isEmpty {
          parts.append("[page \(index + 1)]\n\(pageText)")
        }
      } catch {
        continue
      }
    }

    let full = parts.joined(separator: "\n\n")
    let fullTruncated = truncateUtf8(full, maxBytes: 256 * 1024)
    let excerpt = truncateUtf8(fullTruncated, maxBytes: 8 * 1024)
    let isTruncated = processedPages < pageCount || fullTruncated != full

    return [
      "ocr_text_full": fullTruncated,
      "ocr_text_excerpt": excerpt,
      "ocr_engine": "apple_vision",
      "ocr_is_truncated": isTruncated,
      "ocr_page_count": pageCount,
      "ocr_processed_pages": processedPages,
    ]
  }

  @available(macOS 10.15, *)
  private func runImageOcrWithVision(
    imageData: Data,
    languageHints: String
  ) -> [String: Any]? {
    guard let image = NSImage(data: imageData) else {
      return nil
    }
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
          let preparedImage = preparedVisionImage(
            from: cgImage,
            languageHints: languageHints
          ) else {
      return nil
    }

    let recognitionLanguages = visionRecognitionLanguages(from: languageHints)
    let useLanguageCorrection = visionUsesLanguageCorrection(from: languageHints)
    do {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = useLanguageCorrection
      if !recognitionLanguages.isEmpty {
        request.recognitionLanguages = recognitionLanguages
      }
      let handler = VNImageRequestHandler(cgImage: preparedImage, options: [:])
      try handler.perform([request])

      let observations = request.results ?? []
      let lines = recognizedLines(from: observations)

      let full = lines.joined(separator: "\n")
      let fullTruncated = truncateUtf8(full, maxBytes: 256 * 1024)
      let excerpt = truncateUtf8(fullTruncated, maxBytes: 8 * 1024)
      return [
        "ocr_text_full": fullTruncated,
        "ocr_text_excerpt": excerpt,
        "ocr_engine": "apple_vision",
        "ocr_is_truncated": fullTruncated != full,
        "ocr_page_count": 1,
        "ocr_processed_pages": 1,
      ]
    } catch {
      return nil
    }
  }

  @available(macOS 10.15, *)
  private func renderPdfPageAsCgImage(page: PDFPage, dpi: Int) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    if bounds.width <= 0 || bounds.height <= 0 {
      return nil
    }

    let scale = max(1.0, min(6.0, CGFloat(dpi) / 72.0))
    let width = max(1, Int(bounds.width * scale))
    let height = max(1, Int(bounds.height * scale))
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: bounds.height)
    context.scaleBy(x: 1, y: -1)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    return context.makeImage()
  }

  private func visionRecognitionLanguages(from hints: String) -> [String] {
    let normalized = hints
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
    let preferredLower = preferred.lowercased()
    let preferredChineseTag = preferredChineseVisionLanguageTag(
      fromPreferredLanguage: preferredLower
    )
    var languages = [String]()
    switch normalized {
    case "", "device_plus_en":
      if preferredLower.hasPrefix("zh") {
        languages.append(preferredChineseTag)
        languages.append("en-US")
      } else if preferredLower.hasPrefix("ja") {
        languages.append("ja-JP")
        languages.append("en-US")
      } else if preferredLower.hasPrefix("ko") {
        languages.append("ko-KR")
        languages.append("en-US")
      } else if preferredLower.hasPrefix("fr") {
        languages.append("fr-FR")
        languages.append("en-US")
      } else if preferredLower.hasPrefix("de") {
        languages.append("de-DE")
        languages.append("en-US")
      } else if preferredLower.hasPrefix("es") {
        languages.append("es-ES")
        languages.append("en-US")
      } else {
        languages.append("en-US")
      }
    case "en":
      languages.append("en-US")
    case "zh_strict":
      languages.append(preferredChineseTag)
    case "zh_en":
      languages.append(preferredChineseTag)
      languages.append("en-US")
    case "ja_en":
      languages.append("ja-JP")
      languages.append("en-US")
    case "ko_en":
      languages.append("ko-KR")
      languages.append("en-US")
    case "fr_en":
      languages.append("fr-FR")
      languages.append("en-US")
    case "de_en":
      languages.append("de-DE")
      languages.append("en-US")
    case "es_en":
      languages.append("es-ES")
      languages.append("en-US")
    default:
      languages.append("en-US")
    }

    var unique = [String]()
    for lang in languages {
      let trimmed = lang.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || unique.contains(trimmed) {
        continue
      }
      unique.append(trimmed)
    }
    return unique
  }

  private func preferredChineseVisionLanguageTag(fromPreferredLanguage preferred: String) -> String {
    let value = preferred.lowercased()
    if value.contains("hant") ||
      value.contains("zh-hk") ||
      value.contains("zh-mo") ||
      value.contains("zh-tw") {
      return "zh-Hant"
    }
    return "zh-Hans"
  }

  private func visionUsesLanguageCorrection(from hints: String) -> Bool {
    let normalized = hints
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch normalized {
    case "zh_strict":
      return false
    default:
      return true
    }
  }

  private func preparedVisionImage(from image: CGImage, languageHints: String) -> CGImage? {
    let normalized = languageHints
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    // For degraded Chinese scans/watermarks, a simple binarization pass often
    // removes light overlays and improves OCR stability.
    if normalized == "zh_strict" || normalized == "zh_en" {
      return binarizedForOcr(image) ?? image
    }
    return image
  }

  private func binarizedForOcr(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    if width <= 0 || height <= 0 {
      return nil
    }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let bitsPerComponent = 8
    let totalBytes = height * bytesPerRow
    var buffer = [UInt8](repeating: 255, count: totalBytes)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &buffer,
      width: width,
      height: height,
      bitsPerComponent: bitsPerComponent,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(
      x: 0,
      y: 0,
      width: CGFloat(width),
      height: CGFloat(height)
    ))
    context.draw(
      image,
      in: CGRect(
        x: 0,
        y: 0,
        width: CGFloat(width),
        height: CGFloat(height)
      )
    )

    var sumLuma: Int64 = 0
    var pixelCount: Int64 = 0
    var idx = 0
    while idx + 3 < buffer.count {
      let r = Int(buffer[idx])
      let g = Int(buffer[idx + 1])
      let b = Int(buffer[idx + 2])
      let luma = (299 * r + 587 * g + 114 * b) / 1000
      sumLuma += Int64(luma)
      pixelCount += 1
      idx += 4
    }
    if pixelCount <= 0 {
      return context.makeImage()
    }

    let mean = Int(sumLuma / pixelCount)
    let threshold = max(150, min(220, mean - 8))

    idx = 0
    while idx + 3 < buffer.count {
      let r = Int(buffer[idx])
      let g = Int(buffer[idx + 1])
      let b = Int(buffer[idx + 2])
      let luma = (299 * r + 587 * g + 114 * b) / 1000
      let v: UInt8 = luma >= threshold ? 255 : 0
      buffer[idx] = v
      buffer[idx + 1] = v
      buffer[idx + 2] = v
      buffer[idx + 3] = 255
      idx += 4
    }

    return context.makeImage()
  }

  @available(macOS 10.15, *)
  private func recognizedLines(from observations: [VNRecognizedTextObservation]) -> [String] {
    let sorted = observations.sorted { lhs, rhs in
      let yGap = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
      if yGap > 0.02 {
        return lhs.boundingBox.midY > rhs.boundingBox.midY
      }
      return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    var lines = sorted.compactMap { obs -> String? in
      guard let candidate = obs.topCandidates(1).first else {
        return nil
      }
      if candidate.confidence < 0.18 {
        return nil
      }
      let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : text
    }
    if !lines.isEmpty {
      return lines
    }

    lines = sorted.compactMap { obs in
      let text = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return text.isEmpty ? nil : text
    }
    return lines
  }

  private func truncateUtf8(_ text: String, maxBytes: Int) -> String {
    let data = Data(text.utf8)
    if data.count <= maxBytes {
      return text
    }
    if maxBytes <= 0 {
      return ""
    }

    var end = maxBytes
    while end > 0 && (data[end] & 0b1100_0000) == 0b1000_0000 {
      end -= 1
    }
    if end <= 0 {
      return ""
    }
    return String(decoding: data.prefix(end), as: UTF8.self)
  }
}

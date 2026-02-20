import UIKit
import Flutter
import workmanager
import ImageIO
import CoreLocation
import PDFKit
import Vision

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private struct PdfRenderPreset {
    let id: String
    let maxPages: Int
    let dpi: Int
  }

  private let commonPdfOcrPreset = PdfRenderPreset(
    id: "common_ocr_v1",
    maxPages: 10_000,
    dpi: 180
  )

  private var locationManager: CLLocationManager?
  private var pendingLocationResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "secondloop/exif",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }

        switch call.method {
        case "extractImageMetadata":
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String,
                !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result(nil)
            return
          }
          result(self.extractImageMetadata(path: path))
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let locationChannel = FlutterMethodChannel(
        name: "secondloop/location",
        binaryMessenger: controller.binaryMessenger
      )
      locationChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }

        switch call.method {
        case "getCurrentLocation":
          self.handleGetCurrentLocation(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let audioTranscodeChannel = FlutterMethodChannel(
        name: "secondloop/audio_transcode",
        binaryMessenger: controller.binaryMessenger
      )
      audioTranscodeChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }

        switch call.method {
        case "transcodeToM4a":
          self.handleTranscodeToM4a(call: call, result: result)
        case "decodeToWavPcm16Mono16k":
          self.handleDecodeToWavPcm16Mono16k(call: call, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      configureAudioTranscribeChannel(
        binaryMessenger: controller.binaryMessenger
      )

      let ocrChannel = FlutterMethodChannel(
        name: "secondloop/ocr",
        binaryMessenger: controller.binaryMessenger
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
        case "renderPdfToLongImage":
          self.handleRenderPdfToLongImage(call: call, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerTask(withIdentifier: "com.secondloop.secondloop.backgroundSync")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleGetCurrentLocation(result: @escaping FlutterResult) {
    if pendingLocationResult != nil {
      result(nil)
      return
    }

    pendingLocationResult = result

    let manager = locationManager ?? CLLocationManager()
    locationManager = manager
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

    let status: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      status = manager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }

    switch status {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finishPendingLocation(nil)
    @unknown default:
      finishPendingLocation(nil)
    }
  }

  private func finishPendingLocation(_ payload: [String: Any]?) {
    guard let result = pendingLocationResult else { return }
    pendingLocationResult = nil
    result(payload)
  }

  @available(iOS 14.0, *)
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard pendingLocationResult != nil else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finishPendingLocation(nil)
    case .notDetermined:
      break
    @unknown default:
      finishPendingLocation(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if #available(iOS 14.0, *) {
      return
    }
    guard pendingLocationResult != nil else { return }
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finishPendingLocation(nil)
    case .notDetermined:
      break
    @unknown default:
      finishPendingLocation(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else {
      finishPendingLocation(nil)
      return
    }

    finishPendingLocation(["latitude": loc.coordinate.latitude, "longitude": loc.coordinate.longitude])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finishPendingLocation(nil)
  }

  private func extractImageMetadata(path: String) -> [String: Any]? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    guard let rawProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
      return nil
    }
    guard let props = rawProps as? [CFString: Any] else {
      return nil
    }

    var out: [String: Any] = [:]

    let dateCandidates: [String?] = [
      (props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String,
      (props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeDigitized] as? String,
      (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String,
    ]
    for raw in dateCandidates {
      if let ms = parseExifDateTimeMsUtc(raw) {
        out["capturedAtMsUtc"] = ms
        break
      }
    }

    if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
       let rawLat = gps[kCGImagePropertyGPSLatitude] as? Double,
       let rawLon = gps[kCGImagePropertyGPSLongitude] as? Double {
      var lat = rawLat
      var lon = rawLon

      if let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String {
        if latRef.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "S" {
          lat = -abs(lat)
        }
      }
      if let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
        if lonRef.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "W" {
          lon = -abs(lon)
        }
      }

      out["latitude"] = lat
      out["longitude"] = lon
    }

    return out.isEmpty ? nil : out
  }

  private func parseExifDateTimeMsUtc(_ raw: String?) -> Int64? {
    guard var value = raw?.split(separator: "\u{0000}").first.map(String.init) else {
      return nil
    }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return nil }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

    guard let date = formatter.date(from: value) else {
      return nil
    }
    return Int64(date.timeIntervalSince1970 * 1000.0)
  }

  private func handleOcrPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
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
    guard #available(iOS 13.0, *) else {
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

  private func handleRenderPdfToLongImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(nil)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let typed = args["bytes"] as? FlutterStandardTypedData else {
      result(nil)
      return
    }

    let preset = resolvePdfRenderPreset(args)

    DispatchQueue.global(qos: .userInitiated).async {
      let payload = self.renderPdfToLongImage(
        pdfData: typed.data,
        maxPages: preset.maxPages,
        dpi: preset.dpi
      )
      DispatchQueue.main.async {
        result(payload)
      }
    }
  }

  private func resolvePdfRenderPreset(_ args: [String: Any]) -> PdfRenderPreset {
    let presetId = (args["ocr_model_preset"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    if presetId == commonPdfOcrPreset.id {
      return commonPdfOcrPreset
    }

    let maxPages = normalizePositiveInt(
      args["max_pages"],
      fallback: commonPdfOcrPreset.maxPages,
      upperBound: 10_000
    )
    let dpi = normalizePositiveInt(
      args["dpi"],
      fallback: commonPdfOcrPreset.dpi,
      upperBound: 600
    )
    return PdfRenderPreset(
      id: presetId.isEmpty ? commonPdfOcrPreset.id : presetId,
      maxPages: maxPages,
      dpi: dpi
    )
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

  @available(iOS 13.0, *)
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

        let observations = request.results as? [VNRecognizedTextObservation] ?? []
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

  @available(iOS 13.0, *)
  private func runImageOcrWithVision(
    imageData: Data,
    languageHints: String
  ) -> [String: Any]? {
    guard let image = UIImage(data: imageData),
          let cgImage = image.cgImage,
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

      let observations = request.results as? [VNRecognizedTextObservation] ?? []
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

  @available(iOS 13.0, *)
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

    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    return context.makeImage()
  }

  @available(iOS 13.0, *)
  private func renderPdfToLongImage(
    pdfData: Data,
    maxPages: Int,
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
    let maxOutputWidth = 1536
    let maxOutputHeight = 20_000
    let maxOutputPixels = 20_000_000

    var pageImages = [CGImage]()
    var totalHeight = 0
    var outputWidth = 0
    var processedPages = 0

    for index in 0..<targetPages {
      guard let page = document.page(at: index),
            let rawImage = renderPdfPageAsCgImage(page: page, dpi: dpi) else {
        continue
      }

      var image = rawImage
      if image.width > maxOutputWidth {
        let ratio = CGFloat(maxOutputWidth) / CGFloat(image.width)
        let resizedHeight = max(1, Int(CGFloat(image.height) * ratio))
        if let resized = resizeCgImage(image, width: maxOutputWidth, height: resizedHeight) {
          image = resized
        }
      }

      let nextHeight = totalHeight + image.height
      let nextWidth = max(outputWidth, image.width)
      if nextHeight > maxOutputHeight { break }
      if nextWidth * nextHeight > maxOutputPixels { break }

      pageImages.append(image)
      totalHeight = nextHeight
      outputWidth = nextWidth
      processedPages += 1
    }

    if pageImages.isEmpty || outputWidth <= 0 || totalHeight <= 0 {
      return nil
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: outputWidth,
      height: totalHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: totalHeight))

    var offsetY = 0
    for image in pageImages {
      let drawRect = CGRect(
        x: 0,
        y: totalHeight - offsetY - image.height,
        width: image.width,
        height: image.height
      )
      context.draw(image, in: drawRect)
      offsetY += image.height
    }

    guard let merged = context.makeImage() else {
      return nil
    }

    let uiImage = UIImage(cgImage: merged)
    guard let jpegData = uiImage.jpegData(compressionQuality: 0.82), !jpegData.isEmpty else {
      return nil
    }

    return [
      "image_bytes": FlutterStandardTypedData(bytes: jpegData),
      "image_mime_type": "image/jpeg",
      "page_count": pageCount,
      "processed_pages": processedPages,
    ]
  }

  private func resizeCgImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    if width <= 0 || height <= 0 { return nil }
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
    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  private func visionRecognitionLanguages(from hints: String) -> [String] {
    let normalized = hints
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    func deduped(_ languages: [String]) -> [String] {
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

    if normalized.isEmpty || normalized == "device_plus_en" {
      let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
      let preferredLower = preferred.lowercased()
      let localeMapping: [(String, [String])] = [
        ("zh", ["zh-Hans", "zh-Hant", "en-US"]),
        ("ja", ["ja-JP", "en-US"]),
        ("ko", ["ko-KR", "en-US"]),
        ("fr", ["fr-FR", "en-US"]),
        ("de", ["de-DE", "en-US"]),
        ("es", ["es-ES", "en-US"]),
      ]
      for (prefix, languages) in localeMapping where preferredLower.hasPrefix(prefix) {
        return deduped(languages)
      }
      return ["en-US"]
    }

    let explicitMapping: [String: [String]] = [
      "en": ["en-US"],
      "zh_strict": ["zh-Hans", "zh-Hant"],
      "zh_en": ["zh-Hans", "zh-Hant", "en-US"],
      "ja_en": ["ja-JP", "en-US"],
      "ko_en": ["ko-KR", "en-US"],
      "fr_en": ["fr-FR", "en-US"],
      "de_en": ["de-DE", "en-US"],
      "es_en": ["es-ES", "en-US"],
    ]

    return deduped(explicitMapping[normalized] ?? ["en-US"])
  }
  private func visionUsesLanguageCorrection(from hints: String) -> Bool {
    hints.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "zh_strict"
  }

  private func preparedVisionImage(from image: CGImage, languageHints: String) -> CGImage? {
    let normalized = languageHints
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
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

    context.setFillColor(UIColor.white.cgColor)
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

  @available(iOS 13.0, *)
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

import UIKit
import Flutter
import workmanager
import ImageIO
import CoreLocation
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
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

    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(url: outputUrl, fileType: .m4a)
    } catch {
      completion(false)
      return
    }

    let channelCount = mono ? 1 : 2
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

    let queue = DispatchQueue(label: "secondloop.audio_transcode.ios")
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
}

import AVFoundation
import Flutter
import UIKit

extension AppDelegate {
  func handleTranscodeToM4a(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

  func handleExtractPreviewPosterJpeg(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

    extractPreviewPosterJpeg(
      inputPath: inputPath,
      outputPath: outputPath
    ) { ok in
      result(ok)
    }
  }


  func handleExtractPreviewFramesJpeg(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let inputPathRaw = args["input_path"] as? String,
          let outputDirRaw = args["output_dir"] as? String else {
      result(nil)
      return
    }

    let inputPath = inputPathRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    let outputDirPath = outputDirRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    if inputPath.isEmpty || outputDirPath.isEmpty {
      result(nil)
      return
    }

    let maxKeyframes = max(1, min(48, args["max_keyframes"] as? Int ?? 24))
    let frameIntervalSeconds = max(1, min(600, args["frame_interval_seconds"] as? Int ?? 8))

    extractPreviewFramesJpeg(
      inputPath: inputPath,
      outputDirPath: outputDirPath,
      maxKeyframes: maxKeyframes,
      frameIntervalSeconds: frameIntervalSeconds
    ) { payload in
      result(payload)
    }
  }

  func handleDecodeToWavPcm16Mono16k(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

    decodeToWavPcm16Mono16k(
      inputPath: inputPath,
      outputPath: outputPath
    ) { ok in
      result(ok)
    }
  }

  private func extractPreviewPosterJpeg(
    inputPath: String,
    outputPath: String,
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

    DispatchQueue.global(qos: .userInitiated).async {
      let asset = AVAsset(url: inputUrl)
      guard asset.tracks(withMediaType: .video).isEmpty == false else {
        DispatchQueue.main.async {
          completion(false)
        }
        return
      }

      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.requestedTimeToleranceBefore = CMTime.positiveInfinity
      generator.requestedTimeToleranceAfter = CMTime.positiveInfinity

      let cgImage: CGImage
      do {
        cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
      } catch {
        DispatchQueue.main.async {
          completion(false)
        }
        return
      }

      let image = UIImage(cgImage: cgImage)
      guard let jpegData = image.jpegData(compressionQuality: 0.82),
            jpegData.isEmpty == false else {
        DispatchQueue.main.async {
          completion(false)
        }
        return
      }

      let ok: Bool
      do {
        try jpegData.write(to: outputUrl, options: .atomic)
        ok = FileManager.default.fileExists(atPath: outputPath)
      } catch {
        ok = false
      }

      DispatchQueue.main.async {
        completion(ok)
      }
    }
  }


  private func extractPreviewFramesJpeg(
    inputPath: String,
    outputDirPath: String,
    maxKeyframes: Int,
    frameIntervalSeconds: Int,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    let inputUrl = URL(fileURLWithPath: inputPath)
    let outputDirUrl = URL(fileURLWithPath: outputDirPath, isDirectory: true)

    do {
      try FileManager.default.createDirectory(
        at: outputDirUrl,
        withIntermediateDirectories: true
      )
    } catch {
      completion(nil)
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let asset = AVAsset(url: inputUrl)
      guard asset.tracks(withMediaType: .video).isEmpty == false else {
        DispatchQueue.main.async {
          completion(nil)
        }
        return
      }

      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.requestedTimeToleranceBefore = CMTime.positiveInfinity
      generator.requestedTimeToleranceAfter = CMTime.positiveInfinity

      let durationSeconds = CMTimeGetSeconds(asset.duration)
      let durationMs = durationSeconds.isFinite
        ? max(0, Int((durationSeconds * 1000.0).rounded()))
        : 0
      let intervalMs = max(1, frameIntervalSeconds) * 1000

      let posterPath = outputDirUrl
        .appendingPathComponent("poster.jpg")
        .path
      let posterOk = self.writePreviewFrameAsJpeg(
        generator: generator,
        timeMs: 0,
        outputPath: posterPath
      )

      var keyframes = [[String: Any]]()
      var seenHashes = Set<Int>()
      var timeMs = 0
      let maxDurationMs = durationMs > 0 ? durationMs : intervalMs * maxKeyframes

      while keyframes.count < maxKeyframes && timeMs <= maxDurationMs {
        let filename = String(format: "keyframe_%03d.jpg", keyframes.count)
        let outputPath = outputDirUrl.appendingPathComponent(filename).path
        if self.writePreviewFrameAsJpeg(
          generator: generator,
          timeMs: timeMs,
          outputPath: outputPath
        ) {
          let frameUrl = URL(fileURLWithPath: outputPath)
          let data = try? Data(contentsOf: frameUrl)
          if let frameData = data, frameData.isEmpty == false {
            let hash = frameData.hashValue
            if seenHashes.insert(hash).inserted {
              keyframes.append([
                "path": outputPath,
                "t_ms": timeMs,
              ])
            } else {
              try? FileManager.default.removeItem(at: frameUrl)
            }
          }
        }
        timeMs += intervalMs
      }

      if keyframes.isEmpty && posterOk {
        keyframes.append([
          "path": posterPath,
          "t_ms": 0,
        ])
      }

      let payload: [String: Any] = [
        "poster_path": posterOk ? posterPath : NSNull(),
        "keyframes": keyframes,
      ]
      DispatchQueue.main.async {
        completion(payload)
      }
    }
  }

  private func writePreviewFrameAsJpeg(
    generator: AVAssetImageGenerator,
    timeMs: Int,
    outputPath: String
  ) -> Bool {
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
      return false
    }

    let safeTimeMs = max(0, timeMs)
    let time = CMTime(value: Int64(safeTimeMs), timescale: 1000)

    let cgImage: CGImage
    do {
      cgImage = try generator.copyCGImage(at: time, actualTime: nil)
    } catch {
      return false
    }

    let image = UIImage(cgImage: cgImage)
    guard let jpegData = image.jpegData(compressionQuality: 0.82),
          jpegData.isEmpty == false else {
      return false
    }

    do {
      try jpegData.write(to: outputUrl, options: .atomic)
      return FileManager.default.fileExists(atPath: outputPath)
    } catch {
      return false
    }
  }

  private func decodeToWavPcm16Mono16k(
    inputPath: String,
    outputPath: String,
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

    let outputPcmSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVLinearPCMIsBigEndianKey: false,
    ]

    let readerOutput = AVAssetReaderTrackOutput(
      track: audioTrack,
      outputSettings: outputPcmSettings
    )
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else {
      completion(false)
      return
    }
    reader.add(readerOutput)

    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(url: outputUrl, fileType: .wav)
    } catch {
      completion(false)
      return
    }

    let writerInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: outputPcmSettings
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

    let queue = DispatchQueue(label: "secondloop.audio_decode.ios")
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

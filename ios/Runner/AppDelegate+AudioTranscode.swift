import AVFoundation
import Flutter

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

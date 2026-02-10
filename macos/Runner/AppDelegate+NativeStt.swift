import Cocoa
import FlutterMacOS
import Speech

extension AppDelegate {
  private func handleNativeSttTranscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(macOS 10.15, *) else {
      result(
        FlutterError(
          code: "native_stt_unavailable",
          message: "Speech recognition requires macOS 10.15+",
          details: nil
        )
      )
      return
    }

    guard let args = call.arguments as? [String: Any],
          let filePathRaw = args["file_path"] as? String else {
      result(
        FlutterError(
          code: "native_stt_invalid_args",
          message: "Missing file_path",
          details: nil
        )
      )
      return
    }

    let filePath = filePathRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    if filePath.isEmpty || !FileManager.default.fileExists(atPath: filePath) {
      result(
        FlutterError(
          code: "native_stt_file_missing",
          message: "Audio file does not exist",
          details: nil
        )
      )
      return
    }

    let preferredLang = (args["lang"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    runNativeSttTranscribe(
      audioFilePath: filePath,
      preferredLang: preferredLang
    ) { payload, errorMessage in
      DispatchQueue.main.async {
        if let errorMessage = errorMessage {
          result(
            FlutterError(
              code: "native_stt_failed",
              message: errorMessage,
              details: nil
            )
          )
          return
        }
        result(payload)
      }
    }
  }

  @available(macOS 10.15, *)
  private func runNativeSttTranscribe(
    audioFilePath: String,
    preferredLang: String,
    completion: @escaping ([String: Any]?, String?) -> Void
  ) {
    requestSpeechAuthorizationIfNeeded { [weak self] authorized, authError in
      guard let self = self else {
        completion(nil, "native_stt_unavailable")
        return
      }
      guard authorized else {
        completion(nil, authError ?? "speech_authorization_denied")
        return
      }

      guard let recognizer = self.preferredSpeechRecognizer(
        for: preferredLang
      ) else {
        completion(nil, "speech_recognizer_unavailable")
        return
      }
      guard recognizer.supportsOnDeviceRecognition else {
        completion(nil, "speech_on_device_unavailable")
        return
      }

      let request = SFSpeechURLRecognitionRequest(
        url: URL(fileURLWithPath: audioFilePath)
      )
      request.shouldReportPartialResults = false
      request.requiresOnDeviceRecognition = true

      var didComplete = false
      var task: SFSpeechRecognitionTask?

      func finish(payload: [String: Any]?, error: String?) {
        if didComplete {
          return
        }
        didComplete = true
        task?.cancel()
        completion(payload, error)
      }

      task = recognizer.recognitionTask(with: request) { speechResult, error in
        if let error = error {
          finish(payload: nil, error: error.localizedDescription)
          return
        }
        guard let speechResult = speechResult, speechResult.isFinal else {
          return
        }

        let transcript = speechResult.bestTranscription.formattedString
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isEmpty {
          finish(payload: nil, error: "speech_transcript_empty")
          return
        }

        var segments = [[String: Any]]()
        for segment in speechResult.bestTranscription.segments {
          let text = segment.substring.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          if text.isEmpty {
            continue
          }
          segments.append([
            "t_ms": Int((segment.timestamp * 1000).rounded()),
            "text": text,
          ])
        }

        var payload: [String: Any] = [
          "text": transcript,
        ]
        if let last = speechResult.bestTranscription.segments.last {
          let durationMs = Int(((last.timestamp + last.duration) * 1000).rounded())
          payload["duration_ms"] = durationMs
        }
        if !segments.isEmpty {
          payload["segments"] = segments
        }

        finish(payload: payload, error: nil)
      }
    }
  }

  @available(macOS 10.15, *)
  private func requestSpeechAuthorizationIfNeeded(
    completion: @escaping (Bool, String?) -> Void
  ) {
    let status = SFSpeechRecognizer.authorizationStatus()
    switch status {
    case .authorized:
      completion(true, nil)
    case .denied:
      completion(false, "speech_authorization_denied")
    case .restricted:
      completion(false, "speech_authorization_restricted")
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { nextStatus in
        switch nextStatus {
        case .authorized:
          completion(true, nil)
        case .denied:
          completion(false, "speech_authorization_denied")
        case .restricted:
          completion(false, "speech_authorization_restricted")
        case .notDetermined:
          completion(false, "speech_authorization_not_determined")
        @unknown default:
          completion(false, "speech_authorization_unknown")
        }
      }
    @unknown default:
      completion(false, "speech_authorization_unknown")
    }
  }

  @available(macOS 10.15, *)
  private func preferredSpeechRecognizer(for lang: String) -> SFSpeechRecognizer? {
    for localeId in nativeSttLocaleCandidates(for: lang) {
      if let recognizer = SFSpeechRecognizer(
        locale: Locale(identifier: localeId)
      ) {
        return recognizer
      }
    }
    return SFSpeechRecognizer()
  }

  private func nativeSttLocaleCandidates(for lang: String) -> [String] {
    let normalized = lang
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")
      .lowercased()

    var candidates = [String]()
    if normalized.hasPrefix("zh") {
      candidates.append("zh-CN")
      candidates.append("zh-TW")
      candidates.append("en-US")
    } else if normalized.hasPrefix("ja") {
      candidates.append("ja-JP")
      candidates.append("en-US")
    } else if normalized.hasPrefix("ko") {
      candidates.append("ko-KR")
      candidates.append("en-US")
    } else if normalized.hasPrefix("fr") {
      candidates.append("fr-FR")
      candidates.append("en-US")
    } else if normalized.hasPrefix("de") {
      candidates.append("de-DE")
      candidates.append("en-US")
    } else if normalized.hasPrefix("es") {
      candidates.append("es-ES")
      candidates.append("en-US")
    } else if normalized.hasPrefix("en") {
      candidates.append("en-US")
    } else if !normalized.isEmpty {
      candidates.append(normalized)
      candidates.append("en-US")
    } else {
      candidates.append("en-US")
    }

    var unique = [String]()
    for value in candidates {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || unique.contains(trimmed) {
        continue
      }
      unique.append(trimmed)
    }
    return unique
  }

}

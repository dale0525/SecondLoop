import Cocoa
import FlutterMacOS
import Speech

private enum AudioTranscribeMethodKind {
  case localRuntime
  case nativeStt

  var unavailableCode: String {
    switch self {
    case .localRuntime:
      return "local_runtime_unavailable"
    case .nativeStt:
      return "native_stt_unavailable"
    }
  }

  var invalidArgsCode: String {
    switch self {
    case .localRuntime:
      return "local_runtime_invalid_args"
    case .nativeStt:
      return "native_stt_invalid_args"
    }
  }

  var fileMissingCode: String {
    switch self {
    case .localRuntime:
      return "local_runtime_file_missing"
    case .nativeStt:
      return "native_stt_file_missing"
    }
  }

  var failedCode: String {
    switch self {
    case .localRuntime:
      return "local_runtime_failed"
    case .nativeStt:
      return "native_stt_failed"
    }
  }

  var requiresOnDeviceRecognition: Bool {
    switch self {
    case .localRuntime:
      return true
    case .nativeStt:
      return false
    }
  }
}

private struct SpeechRecognizerSelection {
  let recognizer: SFSpeechRecognizer
  let localeId: String
}

extension AppDelegate {
  func handleLocalRuntimeTranscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
    handleAudioTranscribe(call: call, result: result, kind: .localRuntime)
  }

  func handleNativeSttTranscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
    handleAudioTranscribe(call: call, result: result, kind: .nativeStt)
  }

  private func handleAudioTranscribe(
    call: FlutterMethodCall,
    result: @escaping FlutterResult,
    kind: AudioTranscribeMethodKind
  ) {
    guard #available(macOS 10.15, *) else {
      result(
        FlutterError(
          code: kind.unavailableCode,
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
          code: kind.invalidArgsCode,
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
          code: kind.fileMissingCode,
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
      preferredLang: preferredLang,
      requiresOnDeviceRecognition: kind.requiresOnDeviceRecognition
    ) { payload, errorMessage in
      DispatchQueue.main.async {
        if let errorMessage = errorMessage {
          result(
            FlutterError(
              code: kind.failedCode,
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
    requiresOnDeviceRecognition: Bool,
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

      guard let selection = self.preferredSpeechRecognizer(
        for: preferredLang,
        requiresOnDeviceRecognition: requiresOnDeviceRecognition
      ) else {
        completion(nil, "speech_recognizer_unavailable")
        return
      }

      let recognizer = selection.recognizer
      let request = SFSpeechURLRecognitionRequest(
        url: URL(fileURLWithPath: audioFilePath)
      )
      request.shouldReportPartialResults = false
      request.requiresOnDeviceRecognition = requiresOnDeviceRecognition

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
          "locale": selection.localeId,
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
  private func speechUsageDescriptionPreflightError() -> String? {
    let usageDescription = (Bundle.main.object(
      forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"
    ) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    if !usageDescription.isEmpty {
      return nil
    }

    NSLog(
      "SecondLoop native stt blocked: missing NSSpeechRecognitionUsageDescription in bundle \(Bundle.main.bundlePath)"
    )
    return "speech_usage_description_missing"
  }

  @available(macOS 10.15, *)
  private func requestSpeechAuthorizationIfNeeded(
    completion: @escaping (Bool, String?) -> Void
  ) {
    func resolve(_ authorized: Bool, _ error: String?) {
      if Thread.isMainThread {
        completion(authorized, error)
      } else {
        DispatchQueue.main.async {
          completion(authorized, error)
        }
      }
    }

    if let preflightError = speechUsageDescriptionPreflightError() {
      resolve(false, preflightError)
      return
    }

    let status = SFSpeechRecognizer.authorizationStatus()
    switch status {
    case .authorized:
      resolve(true, nil)
    case .denied:
      resolve(false, "speech_authorization_denied")
    case .restricted:
      resolve(false, "speech_authorization_restricted")
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { nextStatus in
        switch nextStatus {
        case .authorized:
          resolve(true, nil)
        case .denied:
          resolve(false, "speech_authorization_denied")
        case .restricted:
          resolve(false, "speech_authorization_restricted")
        case .notDetermined:
          resolve(false, "speech_authorization_not_determined")
        @unknown default:
          resolve(false, "speech_authorization_unknown")
        }
      }
    @unknown default:
      resolve(false, "speech_authorization_unknown")
    }
  }

  @available(macOS 10.15, *)
  private func preferredSpeechRecognizer(
    for lang: String,
    requiresOnDeviceRecognition: Bool
  ) -> SpeechRecognizerSelection? {
    var deferredSelection: SpeechRecognizerSelection?

    for localeId in nativeSttLocaleCandidates(for: lang) {
      let locale = Locale(identifier: localeId)
      guard let recognizer = SFSpeechRecognizer(locale: locale) else {
        continue
      }
      if requiresOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
        continue
      }

      let canonicalId = locale.identifier.replacingOccurrences(of: "_", with: "-")
      let selection = SpeechRecognizerSelection(
        recognizer: recognizer,
        localeId: canonicalId
      )

      if recognizer.isAvailable {
        return selection
      }
      if deferredSelection == nil {
        deferredSelection = selection
      }
    }

    if let deferredSelection = deferredSelection {
      return deferredSelection
    }

    guard !requiresOnDeviceRecognition,
          let recognizer = SFSpeechRecognizer() else {
      return nil
    }

    let localeId = recognizer.locale.identifier.replacingOccurrences(of: "_", with: "-")
    return SpeechRecognizerSelection(
      recognizer: recognizer,
      localeId: localeId
    )
  }

  private func nativeSttLocaleCandidates(for lang: String) -> [String] {
    let normalized = lang
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")

    let lower = normalized.lowercased()
    var candidates = [String]()

    func appendUnique(_ value: String) {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        return
      }
      let canonical = trimmed.replacingOccurrences(of: "_", with: "-")
      let key = canonical.lowercased()
      for existing in candidates {
        if existing.lowercased() == key {
          return
        }
      }
      candidates.append(canonical)
    }

    func appendLanguageAndBase(_ value: String) {
      let canonical = value.replacingOccurrences(of: "_", with: "-")
      appendUnique(canonical)
      if let range = canonical.range(of: "-") {
        appendUnique(String(canonical[..<range.lowerBound]))
      }
    }

    let isAutoLanguage =
      lower.isEmpty || lower == "auto" || lower == "und" || lower == "unknown"

    if isAutoLanguage {
      for preferred in Locale.preferredLanguages {
        appendLanguageAndBase(preferred)
      }
      appendLanguageAndBase(Locale.current.identifier)
      appendLanguageAndBase(Locale.autoupdatingCurrent.identifier)
      appendUnique("zh-CN")
      appendUnique("zh-TW")
      appendUnique("en-US")
    } else {
      appendLanguageAndBase(normalized)

      if lower.hasPrefix("zh") {
        if lower.contains("hant") || lower.hasSuffix("-tw") || lower.hasSuffix("-hk") || lower.hasSuffix("-mo") {
          appendUnique("zh-TW")
          appendUnique("zh-HK")
          appendUnique("zh-CN")
        } else {
          appendUnique("zh-CN")
          appendUnique("zh-TW")
        }
      } else if lower.hasPrefix("ja") {
        appendUnique("ja-JP")
      } else if lower.hasPrefix("ko") {
        appendUnique("ko-KR")
      } else if lower.hasPrefix("fr") {
        appendUnique("fr-FR")
      } else if lower.hasPrefix("de") {
        appendUnique("de-DE")
      } else if lower.hasPrefix("es") {
        appendUnique("es-ES")
      } else if lower.hasPrefix("en") {
        appendUnique("en-US")
      }
    }

    if candidates.isEmpty {
      appendUnique("en-US")
    }

    return candidates
  }
}

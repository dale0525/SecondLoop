import Flutter
import Speech

private struct NativeSpeechRecognizerSelection {
  let recognizer: SFSpeechRecognizer
  let localeId: String
}

private var speechAuthorizationInFlight = false
private var speechAuthorizationWaiters = [((Bool, String?) -> Void)]()

extension AppDelegate {
  func configureAudioTranscribeChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let audioTranscribeChannel = FlutterMethodChannel(
      name: "secondloop/audio_transcribe",
      binaryMessenger: binaryMessenger
    )
    audioTranscribeChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }

      switch call.method {
      case "nativeSttTranscribe":
        self.handleNativeSttTranscribe(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleNativeSttTranscribe(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 13.0, *) else {
      result(
        FlutterError(
          code: "native_stt_unavailable",
          message: "Speech recognition requires iOS 13+",
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

  @available(iOS 13.0, *)
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
        completion(nil, authError ?? "speech_permission_denied")
        return
      }

      guard let selection = self.preferredSpeechRecognizer(for: preferredLang) else {
        completion(nil, "speech_runtime_unavailable")
        return
      }

      let request = SFSpeechURLRecognitionRequest(
        url: URL(fileURLWithPath: audioFilePath)
      )
      request.shouldReportPartialResults = false
      request.requiresOnDeviceRecognition = false

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

      task = selection.recognizer.recognitionTask(with: request) { speechResult, error in
        if let error = error {
          finish(payload: nil, error: self.normalizeSpeechRecognitionError(error))
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

  @available(iOS 13.0, *)
  private func normalizeSpeechRecognitionError(_ error: Error) -> String {
    let nsError = error as NSError
    let message = nsError.localizedDescription
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = message.lowercased()

    if lower.contains("not authorized") ||
      lower.contains("permission") ||
      lower.contains("denied") {
      return "speech_permission_denied"
    }

    if lower.contains("restricted") {
      return "speech_permission_restricted"
    }

    if lower.contains("not available") || lower.contains("unavailable") {
      return "speech_runtime_unavailable"
    }

    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101 {
      return "speech_service_disabled"
    }

    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1100 {
      return "speech_runtime_unavailable"
    }

    if message.isEmpty {
      return "speech_runtime_unavailable"
    }

    return message
  }

  @available(iOS 13.0, *)
  private func speechUsageDescriptionPreflightError() -> String? {
    let speechUsage = (Bundle.main.object(
      forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"
    ) as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if speechUsage.isEmpty {
      return "speech_permission_usage_description_missing"
    }
    return nil
  }

  @available(iOS 13.0, *)
  private func requestSpeechAuthorizationIfNeeded(
    completion: @escaping (Bool, String?) -> Void
  ) {
    func enqueue() {
      speechAuthorizationWaiters.append(completion)
      if speechAuthorizationInFlight {
        return
      }
      speechAuthorizationInFlight = true
      runSpeechAuthorizationRequest()
    }

    if Thread.isMainThread {
      enqueue()
      return
    }

    DispatchQueue.main.async {
      enqueue()
    }
  }

  @available(iOS 13.0, *)
  private func runSpeechAuthorizationRequest() {
    if let preflightError = speechUsageDescriptionPreflightError() {
      resolveSpeechAuthorizationWaiters(authorized: false, error: preflightError)
      return
    }

    let status = SFSpeechRecognizer.authorizationStatus()
    switch status {
    case .authorized:
      resolveSpeechAuthorizationWaiters(authorized: true, error: nil)
    case .denied:
      resolveSpeechAuthorizationWaiters(
        authorized: false,
        error: "speech_permission_denied"
      )
    case .restricted:
      resolveSpeechAuthorizationWaiters(
        authorized: false,
        error: "speech_permission_restricted"
      )
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { nextStatus in
        DispatchQueue.main.async {
          switch nextStatus {
          case .authorized:
            self.resolveSpeechAuthorizationWaiters(authorized: true, error: nil)
          case .denied:
            self.resolveSpeechAuthorizationWaiters(
              authorized: false,
              error: "speech_permission_denied"
            )
          case .restricted:
            self.resolveSpeechAuthorizationWaiters(
              authorized: false,
              error: "speech_permission_restricted"
            )
          case .notDetermined:
            self.resolveSpeechAuthorizationWaiters(
              authorized: false,
              error: "speech_permission_not_determined"
            )
          @unknown default:
            self.resolveSpeechAuthorizationWaiters(
              authorized: false,
              error: "speech_permission_unknown"
            )
          }
        }
      }
    @unknown default:
      resolveSpeechAuthorizationWaiters(
        authorized: false,
        error: "speech_permission_unknown"
      )
    }
  }

  @available(iOS 13.0, *)
  private func resolveSpeechAuthorizationWaiters(
    authorized: Bool,
    error: String?
  ) {
    if !Thread.isMainThread {
      DispatchQueue.main.async {
        self.resolveSpeechAuthorizationWaiters(
          authorized: authorized,
          error: error
        )
      }
      return
    }

    let waiters = speechAuthorizationWaiters
    speechAuthorizationWaiters.removeAll(keepingCapacity: true)
    speechAuthorizationInFlight = false

    for waiter in waiters {
      waiter(authorized, error)
    }
  }

  @available(iOS 13.0, *)
  private func preferredSpeechRecognizer(
    for lang: String
  ) -> NativeSpeechRecognizerSelection? {
    var deferredSelection: NativeSpeechRecognizerSelection?

    for localeId in nativeSttLocaleCandidates(for: lang) {
      let locale = Locale(identifier: localeId)
      guard let recognizer = SFSpeechRecognizer(locale: locale) else {
        continue
      }

      let canonicalId = locale.identifier.replacingOccurrences(of: "_", with: "-")
      let selection = NativeSpeechRecognizerSelection(
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

    guard let recognizer = SFSpeechRecognizer() else {
      return nil
    }

    let localeId = recognizer.locale.identifier.replacingOccurrences(of: "_", with: "-")
    return NativeSpeechRecognizerSelection(
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
      appendUnique("en-US")
      return candidates
    }

    appendLanguageAndBase(normalized)
    appendUnique("en-US")
    return candidates
  }
}

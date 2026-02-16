import Cocoa
import FlutterMacOS
import Security
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

private var speechAuthorizationInFlight = false
private var speechAuthorizationWaiters = [((Bool, String?) -> Void)]()

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
        completion(nil, authError ?? "speech_permission_denied")
        return
      }

      guard let selection = self.preferredSpeechRecognizer(
        for: preferredLang,
        requiresOnDeviceRecognition: requiresOnDeviceRecognition
      ) else {
        completion(nil, "speech_runtime_unavailable")
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

  @available(macOS 10.15, *)
  private func normalizeSpeechRecognitionError(_ error: Error) -> String {
    let nsError = error as NSError
    let message = nsError.localizedDescription
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = message.lowercased()

    if lower.contains("siri") &&
      lower.contains("dictation") &&
      (lower.contains("disable") || lower.contains("disabled")) {
      return "speech_service_disabled"
    }

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

  @available(macOS 10.15, *)
  private func usageDescriptionValue(
    forInfoDictionaryKey key: String,
    in dictionary: [String: Any]?
  ) -> String {
    let value = (dictionary?[key] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value
  }

  @available(macOS 10.15, *)
  private func signedInfoPlist() -> [String: Any]? {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(
      Bundle.main.bundleURL as CFURL,
      SecCSFlags(rawValue: 0),
      &staticCode
    )

    guard createStatus == errSecSuccess,
          let staticCode = staticCode else {
      NSLog(
        "SecondLoop native stt warning: failed to read app static code (status: \(createStatus))"
      )
      return nil
    }

    var signingInfo: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &signingInfo
    )

    guard infoStatus == errSecSuccess,
          let signingInfo = signingInfo as? [String: Any],
          let plist = signingInfo[kSecCodeInfoPList as String] as? [String: Any] else {
      NSLog(
        "SecondLoop native stt warning: failed to read app signing info plist (status: \(infoStatus))"
      )
      return nil
    }

    return plist
  }

  @available(macOS 10.15, *)
  private func speechUsageDescriptionPreflightError() -> String? {
    let bundlePath = Bundle.main.bundlePath
    let runtimeInfo = Bundle.main.infoDictionary
    let runtimeSpeechUsage = usageDescriptionValue(
      forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription",
      in: runtimeInfo
    )
    let runtimeMicUsage = usageDescriptionValue(
      forInfoDictionaryKey: "NSMicrophoneUsageDescription",
      in: runtimeInfo
    )

    if runtimeSpeechUsage.isEmpty {
      NSLog(
        "SecondLoop native stt blocked: missing NSSpeechRecognitionUsageDescription in bundle \(bundlePath)"
      )
      return "speech_permission_usage_description_missing"
    }

    if runtimeMicUsage.isEmpty {
      NSLog(
        "SecondLoop native stt blocked: missing NSMicrophoneUsageDescription in bundle \(bundlePath)"
      )
      return "speech_permission_usage_description_missing"
    }

    guard let signedPlist = signedInfoPlist() else {
      return nil
    }

    let signedSpeechUsage = usageDescriptionValue(
      forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription",
      in: signedPlist
    )
    let signedMicUsage = usageDescriptionValue(
      forInfoDictionaryKey: "NSMicrophoneUsageDescription",
      in: signedPlist
    )

    if signedSpeechUsage.isEmpty {
      NSLog(
        "SecondLoop native stt blocked: signed Info.plist missing NSSpeechRecognitionUsageDescription in bundle \(bundlePath)"
      )
      return "speech_permission_usage_description_missing"
    }

    if signedMicUsage.isEmpty {
      NSLog(
        "SecondLoop native stt blocked: signed Info.plist missing NSMicrophoneUsageDescription in bundle \(bundlePath)"
      )
      return "speech_permission_usage_description_missing"
    }

    return nil
  }

  @available(macOS 10.15, *)
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

  @available(macOS 10.15, *)
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

  @available(macOS 10.15, *)
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

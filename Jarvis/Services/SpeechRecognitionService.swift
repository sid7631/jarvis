import Speech
import AVFoundation

/// Handles speech-to-text and wake word detection using SFSpeechRecognizer + AVAudioEngine.
@MainActor
final class SpeechRecognitionService {
    enum Mode {
        case wakeWord
        case activeListening
    }

    // MARK: - Callbacks (always called on main actor)

    var onWakeWordDetected: ((String?) -> Void)?
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onAudioLevel: ((Double) -> Void)?
    var onError: ((String) -> Void)?
    var onDebugEvent: ((String) -> Void)?
    var onModeChanged: ((String) -> Void)?
    var onWakeTranscript: ((String) -> Void)?

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentMode: Mode?
    private var silenceTimer: Timer?
    private var lastResultText: String = ""
    private var isAuthorized = false
    private var recognitionSessionID = UUID()

    nonisolated private func debugLog(_ message: String) {
#if DEBUG
        print("[SpeechRecognitionService] \(message)")
#endif
    }

    private func emitDebugEvent(_ message: String) {
        debugLog(message)
        onDebugEvent?(message)
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            emitDebugEvent("Speech authorization denied: \(speechStatus.rawValue)")
            onError?("Speech recognition not authorized")
            return false
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted: Bool

        switch micStatus {
        case .authorized:
            emitDebugEvent("Microphone authorization already granted")
            micGranted = true
        case .notDetermined:
            emitDebugEvent("Requesting microphone access")
            micGranted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            emitDebugEvent("Microphone authorization status: \(micStatus.rawValue)")
            micGranted = false
        @unknown default:
            emitDebugEvent("Unknown microphone authorization status: \(micStatus.rawValue)")
            micGranted = false
        }

        guard micGranted else {
            emitDebugEvent("Microphone access denied")
            onError?("Microphone access not granted")
            return false
        }

        emitDebugEvent("Speech + microphone permissions granted")
        isAuthorized = true
        return true
    }

    // MARK: - Wake Word Detection

    func startWakeWordDetection() {
        guard isAuthorized else {
            Task {
                let granted = await requestPermissions()
                if granted { startWakeWordDetection() }
            }
            return
        }

        stopListening(forceCancel: true)
        currentMode = .wakeWord
        onModeChanged?("wake")
        emitDebugEvent("Starting wake word detection")
        startRecognition { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                let isFinal = result.isFinal
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if !text.isEmpty {
                        self.onWakeTranscript?(text)
                        self.emitDebugEvent("Wake transcript: \(text)")
                    }

                    if let trailingText = self.extractTrailingText(after: "jarvis", in: text) {
                        self.emitDebugEvent("Wake word detected")
                        self.stopListening()
                        self.onWakeWordDetected?(trailingText)
                        return
                    }

                    if isFinal {
                        self.scheduleWakeWordRestart()
                    }
                }
            }

            if error != nil {
                Task { @MainActor [weak self] in
                    self?.emitDebugEvent("Wake recognition error: \(error?.localizedDescription ?? "unknown")")
                    self?.scheduleWakeWordRestart()
                }
            }
        }
    }

    // MARK: - Active Listening

    func startActiveListening() {
        guard isAuthorized else {
            Task {
                let granted = await requestPermissions()
                if granted { startActiveListening() }
            }
            return
        }

        stopListening(forceCancel: true)
        currentMode = .activeListening
        lastResultText = ""
        resetSilenceTimer()
        onModeChanged?("active")
        emitDebugEvent("Starting active listening")

        startRecognition { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if !text.isEmpty {
                        self.emitDebugEvent("Active transcript: \(text)")
                    }

                    self.lastResultText = text
                    self.onPartialResult?(text)
                    self.resetSilenceTimer()

                    if isFinal {
                        self.finishActiveListening()
                    }
                }
            }

            if error != nil {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.emitDebugEvent("Active recognition error: \(error?.localizedDescription ?? "unknown")")
                    if !self.lastResultText.isEmpty {
                        self.finishActiveListening()
                    } else {
                        self.onError?(error?.localizedDescription ?? "Recognition failed")
                        self.stopListening()
                    }
                }
            }
        }
    }

    // MARK: - Stop

    func stopListening(forceCancel: Bool = false) {
        recognitionSessionID = UUID()
        silenceTimer?.invalidate()
        silenceTimer = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        recognitionRequest?.endAudio()

        if forceCancel {
            recognitionTask?.cancel()
        }

        recognitionTask = nil
        recognitionRequest = nil
        currentMode = nil
        onModeChanged?("idle")
    }

    // MARK: - Private Helpers

    private func startRecognition(resultHandler: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            emitDebugEvent("Speech recognizer unavailable for locale \(speechRecognizer?.locale.identifier ?? "unknown")")
            onError?("Speech recognition unavailable")
            return
        }

        let sessionID = recognitionSessionID

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = currentMode == .wakeWord ? .confirmation : .dictation

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            // Compute RMS audio level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            let level = min(Double(rms * 5), 1.0)

            Task { @MainActor [weak self] in
                self?.onAudioLevel?(level)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            emitDebugEvent("Audio engine started with format: \(recordingFormat)")
        } catch {
            emitDebugEvent("Audio engine failed: \(error.localizedDescription)")
            onError?("Audio engine failed to start: \(error.localizedDescription)")
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            guard sessionID == self.recognitionSessionID else { return }
            resultHandler(result, error)
        }
        emitDebugEvent("Recognition task created. On-device supported: \(speechRecognizer.supportsOnDeviceRecognition)")
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.finishActiveListening()
            }
        }
    }

    private func finishActiveListening() {
        let finalText = lastResultText
        stopListening()
        if !finalText.isEmpty {
            onFinalResult?(finalText)
        }
    }

    private func scheduleWakeWordRestart() {
        guard currentMode == .wakeWord else { return }

        Task { @MainActor [weak self] in
            guard let self, self.currentMode == .wakeWord else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard self.currentMode == .wakeWord else { return }
            self.startWakeWordDetection()
        }
    }

    private func extractTrailingText(after wakeWord: String, in transcript: String) -> String? {
        guard let range = transcript.range(of: wakeWord) else { return nil }

        let trailing = transcript[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if trailing.isEmpty {
            return ""
        }

        return String(trailing)
    }
}

import Speech
import AVFoundation

/// Handles speech-to-text and wake word detection using SFSpeechRecognizer + AVAudioEngine.
///
/// Key design: the AVAudioEngine and its tap run continuously once started.
/// Switching between wake-word and active-listening mode only swaps the
/// SFSpeechAudioBufferRecognitionRequest — the engine never stops between modes,
/// so no audio is dropped in the transition.
@MainActor
final class SpeechRecognitionService {
    enum Mode {
        case wakeWord
        case activeListening
    }

    // MARK: - Callbacks (always called on main actor)

    var onWakeWordDetected: ((String?) -> Void)?
    /// Fired when the user says "stop" during wake word listening.
    var onStopWordDetected: (() -> Void)?
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
            micGranted = true
        case .notDetermined:
            micGranted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            micGranted = false
        @unknown default:
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

        beginRecognitionSession(mode: .wakeWord) { [weak self] result, error in
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
                        // Rotate session so pending callbacks from this task are ignored.
                        // Engine keeps running — startActiveListening will reuse it.
                        self.invalidateCurrentSession()
                        self.onWakeWordDetected?(trailingText)
                        return
                    }

                    if self.detectsStopCommand(in: text) {
                        self.emitDebugEvent("Stop command detected")
                        self.invalidateCurrentSession()
                        self.onStopWordDetected?()
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

        lastResultText = ""

        beginRecognitionSession(mode: .activeListening) { [weak self] result, error in
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
                        self.invalidateCurrentSession()
                        self.onModeChanged?("idle")
                    }
                }
            }
        }

        resetSilenceTimer()
    }

    // MARK: - Full Stop

    /// Completely tears down the audio engine. Only call when going fully offline
    /// (e.g. VoiceManager.stop()). For mode switches, use startWakeWordDetection /
    /// startActiveListening directly — they reuse the running engine.
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

    // MARK: - Private: Session Switching

    /// Starts a new recognition session. If the audio engine is already running
    /// its tap will immediately feed audio into the new request — no gap.
    private func beginRecognitionSession(
        mode: Mode,
        handler: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    ) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            emitDebugEvent("Speech recognizer unavailable")
            onError?("Speech recognition unavailable")
            return
        }

        // Cancel the previous recognition task, but leave the engine running.
        let sessionID = UUID()
        recognitionSessionID = sessionID
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        currentMode = mode
        onModeChanged?(mode == .wakeWord ? "wake" : "active")
        emitDebugEvent(mode == .wakeWord ? "Starting wake word detection" : "Starting active listening")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = mode == .wakeWord ? .confirmation : .dictation
        recognitionRequest = request

        // Ensure the audio engine is running. If already running (the common case
        // during a mode switch), the existing tap starts feeding `request` immediately.
        ensureAudioEngineRunning()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, sessionID == self.recognitionSessionID else { return }
            handler(result, error)
        }
        emitDebugEvent("Recognition task created (on-device: \(speechRecognizer.supportsOnDeviceRecognition))")
    }

    /// Starts the audio engine and installs the tap if not already running.
    /// The tap closure always feeds `self.recognitionRequest`, which is updated
    /// on every mode switch — so no reinstallation is needed.
    private func ensureAudioEngineRunning() {
        guard !audioEngine.isRunning else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard buffer.frameLength > 0 else { return }
            // Feed to whatever request is current — automatically correct after a swap.
            self?.recognitionRequest?.append(buffer)

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
        }
    }

    /// Cancels the current recognition task without stopping the audio engine.
    private func invalidateCurrentSession() {
        recognitionSessionID = UUID()
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        currentMode = nil
    }

    // MARK: - Private: Active Listening Helpers

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
        // Cancel recognition without stopping the engine.
        invalidateCurrentSession()
        onModeChanged?("idle")
        if !finalText.isEmpty {
            onFinalResult?(finalText)
        }
    }

    // MARK: - Private: Wake Word Helpers

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

        // Primary: take text after the wake word ("jarvis open safari" → "open safari")
        let trailing = transcript[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if !trailing.isEmpty { return String(trailing) }

        // Fallback: the recognizer sometimes appends "jarvis" at the very end
        // ("open safari jarvis" / "service open safari jarvis").
        // Use the text that came BEFORE the wake word as the command so the
        // user doesn't have to repeat themselves.
        let preceding = transcript[..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return preceding.isEmpty ? "" : String(preceding)
    }

    private func detectsStopCommand(in transcript: String) -> Bool {
        let words = transcript
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        return words.contains("stop")
    }

    // MARK: - Logging

    private func emitDebugEvent(_ message: String) {
#if DEBUG
        print("[SpeechRecognitionService] \(message)")
#endif
        onDebugEvent?(message)
    }
}

import Observation
import SwiftUI

/// Orchestrates the full voice pipeline: wake word → listen → think → speak → idle.
@Observable
@MainActor
final class VoiceManager {
    private let state: JarvisState
    private let speechSynthesizer: SpeechSynthesizer
    private let recognitionService: SpeechRecognitionService
    private let backend: any BackendService
    private var listeningVerificationTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var shouldResumeWakeListeningAfterSpeech = true
    private var ignoreNextSpeechFinishedCallback = false
    /// Persisted for the lifetime of this VoiceManager so all turns share context.
    private let conversationId = UUID().uuidString

    private(set) var isRunning = false

    init(state: JarvisState, backend: (any BackendService)? = nil) {
        self.state = state
        self.backend = backend ?? FastAPIService()
        self.speechSynthesizer = SpeechSynthesizer()
        self.recognitionService = SpeechRecognitionService()
        setupCallbacks()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        state.errorMessage = nil
        state.debugSpeechMode = "starting"
        state.debugSpeechTranscript = ""
        state.debugSpeechEvent = "Voice manager started"
        playStartupGreeting()
    }

    func stop() {
        isRunning = false
        listeningVerificationTask?.cancel()
        listeningVerificationTask = nil
        cancelStreaming()
        recognitionService.stopListening(forceCancel: true)
        speechSynthesizer.stop()
        state.debugSpeechMode = "stopped"
        state.debugSpeechEvent = "Voice manager stopped"
        transitionTo(.idle)
    }

    /// Manual activation (tap the orb instead of saying "Jarvis").
    func activateManually() {
        switch state.phase {
        case .idle:
            handleWakeWord()
        case .speaking:
            speechSynthesizer.stop()
            returnToIdle()
        case .listening:
            // Force finish listening
            recognitionService.stopListening()
            if !state.transcribedText.isEmpty {
                handleUserSpeech(state.transcribedText)
            } else {
                returnToIdle()
            }
        case .thinking:
            break // Cannot interrupt
        }
    }

    // MARK: - Pipeline

    private func handleWakeWord(initialText: String? = nil) {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = nil
        // Do NOT reset ignoreNextSpeechFinishedCallback here.
        // interruptSpeechAndListen() sets it to true before calling us,
        // and we must preserve that so the async didFinish from stop() is ignored.
        state.errorMessage = nil
        let seededText = initialText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !seededText.isEmpty {
            state.debugSpeechEvent = "Captured inline request after wake word"
            handleUserSpeech(seededText)
            return
        }

        transitionTo(.listening)
        state.transcribedText = ""
        state.responseText = ""
        state.debugSpeechEvent = "Waiting for speech input"
        recognitionService.startActiveListening()
        scheduleListeningVerificationResponse()
    }

    private func handleUserSpeech(_ text: String) {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = nil
        cancelStreaming()
        transitionTo(.thinking)
        state.transcribedText = text
        state.responseText = ""

        streamingTask = Task {
            do {
                let request = ChatRequest(message: text, conversationId: conversationId)
                let stream = try await backend.streamResponse(request)

                var buffer = ""
                var fullResponse = ""
                var spokFirstSentence = false

                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    buffer += chunk
                    fullResponse += chunk
                    state.responseText = fullResponse

                    // Speak each complete sentence as soon as it arrives
                    while let sentence = Self.extractNextSentence(from: &buffer) {
                        if !spokFirstSentence {
                            spokFirstSentence = true
                            transitionTo(.speaking)
                            ignoreNextSpeechFinishedCallback = false
                            speechSynthesizer.speak(sentence)
                            recognitionService.startWakeWordDetection()
                        } else {
                            speechSynthesizer.enqueue(sentence)
                        }
                    }
                }

                guard !Task.isCancelled else { return }

                // Speak any remaining text that didn't end with punctuation
                let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    if spokFirstSentence {
                        speechSynthesizer.enqueue(remainder)
                    } else {
                        // Entire response had no sentence boundary — speak it all at once
                        handleResponse(fullResponse)
                    }
                } else if !spokFirstSentence {
                    handleResponse("I'm sorry, I didn't receive a response.")
                }

            } catch {
                guard !Task.isCancelled else { return }
                state.errorMessage = error.localizedDescription
                handleResponse("I'm sorry, I encountered an issue processing your request.")
            }
        }
    }

    /// Extracts the next complete sentence from the front of `buffer`, mutating it in place.
    /// Splits on `.` `!` `?` followed by a space, newline, or end-of-string.
    private static func extractNextSentence(from buffer: inout String) -> String? {
        let enders: Set<Character> = [".", "!", "?"]
        var i = buffer.startIndex
        while i < buffer.endIndex {
            if enders.contains(buffer[i]) {
                let after = buffer.index(after: i)
                if after == buffer.endIndex || buffer[after] == " " || buffer[after] == "\n" {
                    let sentence = String(buffer[...i]).trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer = after < buffer.endIndex
                        ? String(buffer[after...]).trimmingCharacters(in: CharacterSet(charactersIn: " "))
                        : ""
                    return sentence.isEmpty ? nil : sentence
                }
            }
            i = buffer.index(after: i)
        }
        return nil
    }

    private func handleResponse(_ text: String) {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = nil
        state.responseText = text
        transitionTo(.speaking)
        ignoreNextSpeechFinishedCallback = false
        speechSynthesizer.speak(text)
        recognitionService.startWakeWordDetection()
    }

    private func returnToIdle() {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = nil
        transitionTo(.idle)
        state.transcribedText = ""
        state.responseText = ""
        state.audioLevel = 0
        state.debugSpeechTranscript = ""

        if isRunning {
            if shouldResumeWakeListeningAfterSpeech {
                recognitionService.startWakeWordDetection()
            } else {
                shouldResumeWakeListeningAfterSpeech = true
            }
        }
    }

    private func playStartupGreeting() {
        shouldResumeWakeListeningAfterSpeech = true
        state.responseText = "Good day. Jarvis voice systems are now online."
        state.debugSpeechEvent = "Playing startup greeting"
        transitionTo(.speaking)
        ignoreNextSpeechFinishedCallback = false
        speechSynthesizer.speak(state.responseText)
        recognitionService.startWakeWordDetection()
    }

    private func interruptSpeechAndListen(initialText: String? = nil) {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = nil
        cancelStreaming()
        ignoreNextSpeechFinishedCallback = true
        state.debugSpeechEvent = "Wake word detected during speech"
        speechSynthesizer.stop()
        handleWakeWord(initialText: initialText)
    }

    private func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func scheduleListeningVerificationResponse() {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = Task { [weak self] in
            // 5 seconds: gives the user ample time to speak after an interruption
            // or audio engine restart before the canned verification fires.
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.state.phase == .listening else { return }
            guard self.state.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            self.state.debugSpeechEvent = "No speech detected — returning to idle"
            self.returnToIdle()
        }
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        recognitionService.onWakeWordDetected = { [weak self] trailingText in
            guard let self else { return }
            if self.state.phase == .speaking {
                self.interruptSpeechAndListen(initialText: trailingText)
            } else {
                self.handleWakeWord(initialText: trailingText)
            }
        }

        recognitionService.onStopWordDetected = { [weak self] in
            guard let self else { return }
            switch self.state.phase {
            case .speaking:
                // Stop speech + streaming immediately and return to idle.
                self.cancelStreaming()
                self.ignoreNextSpeechFinishedCallback = true
                self.speechSynthesizer.stop()
                self.returnToIdle()
            case .listening:
                // Cancel active listening and return to idle.
                self.returnToIdle()
            case .idle, .thinking:
                break
            }
        }

        recognitionService.onPartialResult = { [weak self] text in
            self?.listeningVerificationTask?.cancel()
            self?.listeningVerificationTask = nil
            self?.state.errorMessage = nil
            self?.state.transcribedText = text
        }

        recognitionService.onFinalResult = { [weak self] text in
            self?.listeningVerificationTask?.cancel()
            self?.listeningVerificationTask = nil
            self?.state.errorMessage = nil
            self?.handleUserSpeech(text)
        }

        recognitionService.onAudioLevel = { [weak self] level in
            self?.state.audioLevel = level
        }

        recognitionService.onError = { [weak self] message in
            self?.state.errorMessage = message
        }

        recognitionService.onDebugEvent = { [weak self] message in
            self?.state.debugSpeechEvent = message
        }

        recognitionService.onModeChanged = { [weak self] mode in
            self?.state.debugSpeechMode = mode
        }

        recognitionService.onWakeTranscript = { [weak self] text in
            self?.state.debugSpeechTranscript = text
        }

        speechSynthesizer.onFinished = { [weak self] in
            guard let self else { return }
            if self.ignoreNextSpeechFinishedCallback {
                self.ignoreNextSpeechFinishedCallback = false
                return
            }
            // Stale didFinish callbacks can arrive after an interrupt while we
            // are already in listening/idle/thinking. Only act when speaking.
            guard self.state.phase == .speaking else { return }
            self.returnToIdle()
        }
    }

    // MARK: - State Transition

    private func transitionTo(_ phase: AssistantPhase) {
        withAnimation(.jarvisTransition) {
            state.phase = phase
        }
    }
}

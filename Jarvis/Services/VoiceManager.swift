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
    private var shouldResumeWakeListeningAfterSpeech = true
    private var ignoreNextSpeechFinishedCallback = false

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
        ignoreNextSpeechFinishedCallback = false
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
        transitionTo(.thinking)
        state.transcribedText = text

        Task {
            do {
                let request = ChatRequest(message: text, conversationId: nil)
                let response = try await backend.sendMessage(request)
                handleResponse(response.reply)
            } catch {
                state.errorMessage = error.localizedDescription
                handleResponse("I'm sorry, I encountered an issue processing your request.")
            }
        }
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
        ignoreNextSpeechFinishedCallback = true
        state.debugSpeechEvent = "Wake word detected during speech"
        speechSynthesizer.stop()
        handleWakeWord(initialText: initialText)
    }

    private func scheduleListeningVerificationResponse() {
        listeningVerificationTask?.cancel()
        listeningVerificationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.state.phase == .listening else { return }
            guard self.state.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            self.state.debugSpeechEvent = "Using mock reply for voice verification"
            self.recognitionService.stopListening(forceCancel: true)
            self.handleUserSpeech("Voice output verification")
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

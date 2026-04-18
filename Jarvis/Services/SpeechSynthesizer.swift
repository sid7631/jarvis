import AVFoundation

/// Wraps AVSpeechSynthesizer to give Jarvis a voice.
final class SpeechSynthesizer: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var pendingUtterances = 0
    private static let preferredFemaleNames = [
        "serena",
        "martha",
        "karen",
        "moira",
        "samantha",
        "ava",
        "victoria"
    ]

    /// Called on the main actor when ALL queued utterances have finished.
    @MainActor var onFinished: (() -> Void)?

    override init() {
        self.voice = Self.preferredVoice()
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public

    /// Stops any in-progress speech and starts speaking `text` immediately.
    @MainActor
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances = 0
        enqueue(text)
    }

    /// Appends `text` to the speech queue without interrupting the current utterance.
    @MainActor
    func enqueue(_ text: String) {
        pendingUtterances += 1
        synthesizer.speak(makeUtterance(text))
    }

    @MainActor
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances = 0
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingUtterances = max(0, pendingUtterances - 1)
        guard pendingUtterances == 0 else { return }
        Task { @MainActor in self.onFinished?() }
    }

    // MARK: - Private

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        return utterance
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        if let britishFemale = voices.first(where: { voice in
            voice.language == "en-GB" &&
            preferredFemaleNames.contains { name in
                voice.name.lowercased().contains(name)
            }
        }) {
            return britishFemale
        }

        if let englishFemale = voices.first(where: { voice in
            voice.language.hasPrefix("en") &&
            preferredFemaleNames.contains { name in
                voice.name.lowercased().contains(name)
            }
        }) {
            return englishFemale
        }

        return AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

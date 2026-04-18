import AVFoundation

/// Wraps AVSpeechSynthesizer to give Jarvis a voice.
final class SpeechSynthesizer: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private static let preferredFemaleNames = [
        "serena",
        "martha",
        "karen",
        "moira",
        "samantha",
        "ava",
        "victoria"
    ]

    /// Called on the main actor when the current utterance finishes.
    @MainActor var onFinished: (() -> Void)?

    override init() {
        self.voice = Self.preferredVoice()
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public

    @MainActor
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    @MainActor
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onFinished?()
        }
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

import SwiftUI

// MARK: - Assistant Phase

enum AssistantPhase: String, CaseIterable {
    case idle
    case listening
    case thinking
    case speaking
}

// MARK: - Jarvis State

@Observable
class JarvisState {
    var phase: AssistantPhase = .idle
    var responseText: String = ""
    var transcribedText: String = ""
    var errorMessage: String?
    var isConnected: Bool = false
    var debugSpeechMode: String = "idle"
    var debugSpeechTranscript: String = ""
    var debugSpeechEvent: String = ""

    /// Audio input level (0.0 - 1.0) for visualizer reactivity
    var audioLevel: Double = 0.0

    // MARK: - Visual Properties

    var primaryColor: Color {
        switch phase {
        case .idle:      return .jarvisCyan
        case .listening: return .jarvisBlue
        case .thinking:  return .jarvisGold
        case .speaking:  return .jarvisCyanBright
        }
    }

    var secondaryColor: Color {
        switch phase {
        case .idle:      return .jarvisCyanDim
        case .listening: return .jarvisBlueBright
        case .thinking:  return .jarvisGoldDim
        case .speaking:  return .jarvisCyan
        }
    }

    var pulseSpeed: Double {
        switch phase {
        case .idle:      return 3.0
        case .listening: return 1.5
        case .thinking:  return 0.8
        case .speaking:  return 1.2
        }
    }

    var particleCount: Int {
        switch phase {
        case .idle:      return 30
        case .listening: return 60
        case .thinking:  return 100
        case .speaking:  return 80
        }
    }

    // MARK: - Status Text

    var statusText: String {
        if errorMessage != nil {
            return "VOICE ERROR"
        }

        switch phase {
        case .idle:
            return audioLevel > 0.02 ? "WAKE LISTENING..." : "SAY 'JARVIS' OR TAP"
        case .listening: return "LISTENING..."
        case .thinking:  return "PROCESSING..."
        case .speaking:  return "SPEAKING"
        }
    }
}

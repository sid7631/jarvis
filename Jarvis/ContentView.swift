import SwiftUI

struct ContentView: View {
    @Environment(JarvisState.self) private var state
    @State private var voiceManager: VoiceManager?

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 12) {
                Spacer()

                OrbView()
                    .onTapGesture { voiceManager?.activateManually() }

                // Show transcribed text while listening
                if state.phase == .listening, !state.transcribedText.isEmpty {
                    transcriptionLabel(state.transcribedText)
                }

                // Show response while speaking
                if state.phase == .speaking, !state.responseText.isEmpty {
                    transcriptionLabel(state.responseText)
                }

                StatusTextView()

                if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .transition(.opacity)
                }

                debugOverlay

                Spacer()
            }
        }
        .frame(width: JarvisLayout.windowWidth, height: JarvisLayout.windowHeight)
        .background(WindowAccessor())
        .onAppear {
            let manager = VoiceManager(state: state)
            voiceManager = manager
            manager.start()
        }
        .onDisappear {
            voiceManager?.stop()
        }
    }

    @ViewBuilder
    private func transcriptionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(state.primaryColor.opacity(0.6))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 260)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: text)
    }

    @ViewBuilder
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG MODE: \(state.debugSpeechMode)")
            Text("DEBUG AUDIO: \(String(format: "%.3f", state.audioLevel))")
            Text("DEBUG WAKE: \(state.debugSpeechTranscript.isEmpty ? "-" : state.debugSpeechTranscript)")
            Text("DEBUG EVENT: \(state.debugSpeechEvent.isEmpty ? "-" : state.debugSpeechEvent)")
        }
        .font(.system(size: 8, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.72))
        .padding(8)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    ContentView()
        .environment(JarvisState())
        .preferredColorScheme(.dark)
}

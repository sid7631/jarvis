import SwiftUI

/// Displays the current Jarvis phase as styled monospace text below the orb.
struct StatusTextView: View {
    @Environment(JarvisState.self) private var state

    var body: some View {
        Text(state.statusText)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(state.primaryColor.opacity(0.8))
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.3), value: state.phase)
    }
}

import SwiftUI

/// Expanding concentric rings that pulse outward from the orb center.
struct PulseRingView: View {
    @Environment(JarvisState.self) private var state

    @State private var ring1Phase: CGFloat = 0
    @State private var ring2Phase: CGFloat = 0
    @State private var ring3Phase: CGFloat = 0

    private let ringSize: CGFloat = JarvisLayout.orbSize

    var body: some View {
        ZStack {
            // Ring 1: always visible
            pulseRing(phase: ring1Phase, lineWidth: 1.5, color: state.primaryColor, opacity: 0.4)

            // Ring 2: visible when active
            if state.phase != .idle {
                pulseRing(phase: ring2Phase, lineWidth: 1.0, color: state.secondaryColor, opacity: 0.3)
            }

            // Ring 3: thinking only
            if state.phase == .thinking {
                pulseRing(phase: ring3Phase, lineWidth: 0.8, color: state.primaryColor, opacity: 0.2)
            }
        }
        .onAppear { startAnimations() }
        .onChange(of: state.phase) { _, _ in
            resetAndAnimate()
        }
    }

    @ViewBuilder
    private func pulseRing(phase: CGFloat, lineWidth: CGFloat, color: Color, opacity: Double) -> some View {
        let scale = 0.5 + phase * 1.3
        let ringOpacity = opacity * (1.0 - Double(phase))
        Circle()
            .stroke(color.opacity(ringOpacity), lineWidth: lineWidth)
            .frame(width: ringSize, height: ringSize)
            .scaleEffect(scale)
    }

    private func resetAndAnimate() {
        ring1Phase = 0
        ring2Phase = 0
        ring3Phase = 0
        startAnimations()
    }

    private func startAnimations() {
        let speed = state.pulseSpeed

        withAnimation(.easeOut(duration: speed).repeatForever(autoreverses: false)) {
            ring1Phase = 1.0
        }

        withAnimation(.easeOut(duration: speed).repeatForever(autoreverses: false).delay(speed * 0.33)) {
            ring2Phase = 1.0
        }

        withAnimation(.easeOut(duration: speed).repeatForever(autoreverses: false).delay(speed * 0.66)) {
            ring3Phase = 1.0
        }
    }
}

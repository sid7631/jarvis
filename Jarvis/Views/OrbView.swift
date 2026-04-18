import SwiftUI

/// The central Jarvis orb — composites glow, rings, particles, and core.
struct OrbView: View {
    @Environment(JarvisState.self) private var state
    @State private var breathing = false
    @State private var rotation: Double = 0

    private let size = JarvisLayout.orbSize

    var body: some View {
        ZStack {
            // Layer 1: Outer ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [state.primaryColor.opacity(0.25), .clear],
                        center: .center,
                        startRadius: size * 0.2,
                        endRadius: size * 0.9
                    )
                )
                .frame(width: size * 2, height: size * 2)
                .blur(radius: 40)

            // Layer 2: Pulse rings
            PulseRingView()

            // Layer 3: Particles
            OrbCanvasView()
                .frame(width: size * 1.6, height: size * 1.6)

            // Layer 4: Core glow body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            state.primaryColor.opacity(0.8),
                            state.secondaryColor.opacity(0.3),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)
                .blur(radius: 10)
                .rotationEffect(.degrees(rotation))

            // Layer 5: Inner bright core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [state.primaryColor, state.primaryColor.opacity(0.5), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.12
                    )
                )
                .frame(width: size * 0.25, height: size * 0.25)
                .blur(radius: 4)
        }
        .scaleEffect(breathing ? 1.05 : 0.95)
        .animation(.easeInOut(duration: state.pulseSpeed).repeatForever(autoreverses: true), value: breathing)
        .animation(.jarvisTransition, value: state.phase)
        .onAppear {
            breathing = true
            startRotation()
        }
        .onChange(of: state.phase) { _, _ in
            startRotation()
        }
    }

    private func startRotation() {
        let speed: Double = state.phase == .thinking ? 4.0 : 20.0
        withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

#Preview {
    OrbView()
        .frame(width: 300, height: 350)
        .background(.black)
        .environment(JarvisState())
}

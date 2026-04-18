import SwiftUI

/// Renders particles using TimelineView + Canvas for high-performance drawing.
struct OrbCanvasView: View {
    @Environment(JarvisState.self) private var state
    @State private var particleSystem = ParticleSystem()
    @State private var lastUpdate: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) / 2

                for particle in particleSystem.particles {
                    let px = center.x + particle.x * maxRadius
                    let py = center.y + particle.y * maxRadius
                    let particleSize = particle.size

                    let rect = CGRect(
                        x: px - particleSize / 2,
                        y: py - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )

                    context.opacity = particle.opacity * particle.life
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(state.primaryColor)
                    )
                }
            }
            .onChange(of: timeline.date) { oldValue, newValue in
                let dt = lastUpdate.map { newValue.timeIntervalSince($0) } ?? (1.0 / 60.0)
                lastUpdate = newValue
                particleSystem.update(
                    phase: state.phase.rawValue,
                    audioLevel: state.audioLevel,
                    dt: min(dt, 0.1) // Cap delta to prevent jumps
                )
            }
        }
    }

    /// Lower frame rate during idle to save CPU.
    private var frameInterval: Double {
        state.phase == .idle ? (1.0 / 20.0) : (1.0 / 60.0)
    }
}

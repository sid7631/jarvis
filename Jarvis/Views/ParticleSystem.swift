import Foundation

struct Particle {
    var angle: Double       // orbital angle in radians
    var radius: Double      // distance from center (normalized 0...1)
    var speed: Double       // angular velocity (radians/sec)
    var radialSpeed: Double // inward/outward drift
    var opacity: Double
    var size: Double
    var life: Double        // remaining life 0...1

    var x: Double { radius * cos(angle) }
    var y: Double { radius * sin(angle) }
}

class ParticleSystem {
    private(set) var particles: [Particle] = []
    private var targetCount: Int = 30

    func update(phase: String, audioLevel: Double, dt: Double) {
        // Age existing particles
        for i in particles.indices.reversed() {
            particles[i].life -= dt * 0.15
            if particles[i].life <= 0 {
                particles.remove(at: i)
                continue
            }
            // Update position
            particles[i].angle += particles[i].speed * dt
            particles[i].radius += particles[i].radialSpeed * dt
            // Fade out as life decreases
            particles[i].opacity = min(1.0, particles[i].life * 2.0)
            // Clamp radius
            particles[i].radius = max(0.05, min(1.0, particles[i].radius))
        }

        // Spawn new particles up to target
        updateTarget(phase: phase)
        let deficit = targetCount - particles.count
        if deficit > 0 {
            spawn(count: min(deficit, 5), phase: phase, audioLevel: audioLevel)
        }
    }

    private func updateTarget(phase: String) {
        switch phase {
        case "idle":      targetCount = 30
        case "listening": targetCount = 60
        case "thinking":  targetCount = 100
        case "speaking":  targetCount = 80
        default:          targetCount = 30
        }
    }

    private func spawn(count: Int, phase: String, audioLevel: Double) {
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let baseRadius = Double.random(in: 0.3...0.8)
            let speed: Double
            let radialSpeed: Double

            switch phase {
            case "listening":
                // Orbit inward, reactive to audio
                speed = Double.random(in: 1.0...2.5) * (1.0 + audioLevel)
                radialSpeed = Double.random(in: -0.15...(-0.05))
            case "thinking":
                // Fast clockwise orbit
                speed = Double.random(in: 2.0...4.0)
                radialSpeed = Double.random(in: -0.05...0.05)
            case "speaking":
                // Radiate outward
                speed = Double.random(in: 0.5...1.5)
                radialSpeed = Double.random(in: 0.05...0.2)
            default:
                // Idle: slow outward drift
                speed = Double.random(in: 0.2...0.6)
                radialSpeed = Double.random(in: 0.01...0.05)
            }

            let particle = Particle(
                angle: angle,
                radius: baseRadius,
                speed: speed,
                radialSpeed: radialSpeed,
                opacity: Double.random(in: 0.3...0.8),
                size: Double.random(in: 1.5...3.5),
                life: Double.random(in: 0.5...1.0)
            )
            particles.append(particle)
        }
    }
}

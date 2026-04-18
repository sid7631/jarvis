import SwiftUI

// MARK: - Color Palette

extension Color {
    // Arc reactor cyan
    static let jarvisCyan       = Color(red: 0.0, green: 0.85, blue: 1.0)
    static let jarvisCyanBright = Color(red: 0.3, green: 0.95, blue: 1.0)
    static let jarvisCyanDim    = Color(red: 0.0, green: 0.45, blue: 0.6)

    // Listening blue
    static let jarvisBlue       = Color(red: 0.2, green: 0.5, blue: 1.0)
    static let jarvisBlueBright = Color(red: 0.4, green: 0.7, blue: 1.0)

    // Thinking gold
    static let jarvisGold       = Color(red: 1.0, green: 0.75, blue: 0.2)
    static let jarvisGoldDim    = Color(red: 0.7, green: 0.5, blue: 0.1)

    static let jarvisBackground = Color(red: 0.02, green: 0.02, blue: 0.05)
}

// MARK: - Animation Constants

extension Animation {
    static let jarvisBreathing  = Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
    static let jarvisPulse      = Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false)
    static let jarvisTransition = Animation.spring(duration: 0.6, bounce: 0.2)
    static let jarvisSpin       = Animation.linear(duration: 4.0).repeatForever(autoreverses: false)
}

// MARK: - Layout Constants

enum JarvisLayout {
    static let orbSize: CGFloat = 200
    static let windowWidth: CGFloat = 300
    static let windowHeight: CGFloat = 350
}

import SwiftUI

@main
struct JarvisApp: App {
    @State private var jarvisState = JarvisState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(jarvisState)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: JarvisLayout.windowWidth, height: JarvisLayout.windowHeight)
    }
}

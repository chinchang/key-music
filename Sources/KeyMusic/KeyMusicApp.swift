import SwiftUI

@main
struct KeyMusicApp: App {
    @StateObject private var engine = AudioEngine()

    var body: some Scene {
        WindowGroup("KeyMusic") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear { engine.start() }
        }
        .windowResizability(.contentSize)
    }
}

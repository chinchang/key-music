import SwiftUI

@main
struct VibeTypeApp: App {
    @StateObject private var engine = AudioEngine()

    var body: some Scene {
        WindowGroup("VibeType") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear { engine.start() }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("VibeType", systemImage: engine.isEnabled ? "music.note" : "music.note.slash") {
            MenuBarContent(engine: engine)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var engine: AudioEngine

    var body: some View {
        Button(engine.isEnabled ? "Disable" : "Enable") {
            engine.isEnabled.toggle()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

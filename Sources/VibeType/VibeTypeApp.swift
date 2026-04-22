import SwiftUI

@main
struct VibeTypeApp: App {
    @StateObject private var settings = SettingsModel()
    @StateObject private var engine: AudioEngine

    init() {
        let settings = SettingsModel()
        _settings = StateObject(wrappedValue: settings)
        _engine = StateObject(wrappedValue: AudioEngine(settings: settings))
    }

    var body: some Scene {
        WindowGroup("VibeType") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear { engine.start() }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: settings)
        }

        MenuBarExtra("VibeType", systemImage: engine.isEnabled ? "music.note" : "music.note.slash") {
            MenuBarContent(engine: engine)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var engine: AudioEngine
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

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

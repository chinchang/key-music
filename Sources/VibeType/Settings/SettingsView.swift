import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Tempo") {
                HStack {
                    Slider(value: $settings.bpm, in: 60...140, step: 1)
                    Text("\(Int(settings.bpm)) BPM")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }

            Section("Audio") {
                HStack {
                    Slider(value: $settings.masterVolume, in: 0...1)
                    Text("\(Int(settings.masterVolume * 100))%")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }

            Section("Startup") {
                Toggle("Open VibeType at login", isOn: $settings.openAtLogin)
            }
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

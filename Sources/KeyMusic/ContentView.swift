import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: AudioEngine
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("KeyMusic").font(.title2).bold()
                Spacer()
                Text(String(format: "BPM %.0f", engine.bpm))
                Text(String(format: "Intensity %.2f", engine.mapper.intensity))
                    .monospacedDigit()
                Text("Layers: \(engine.layers.activeDescription)")
                    .foregroundStyle(.secondary)
                Text(engine.globalListening ? "● global" : "○ local only")
                    .font(.caption)
                    .foregroundStyle(engine.globalListening ? .green : .orange)
            }
            .padding(.horizontal)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.08)))
                .foregroundStyle(.white)
                .focused($focused)
                .padding(.horizontal)

            Text("Type anything. The base loop is always playing — your typing layers in bass, arps and leads, locked to the grid.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .onAppear { focused = true }
    }
}

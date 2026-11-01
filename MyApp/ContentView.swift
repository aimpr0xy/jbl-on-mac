import SwiftUI

enum ListeningMode: String, CaseIterable, Identifiable {
    case noiseCanceling = "Noise Canceling"
    case ambientAware = "Ambient Aware"
    case talkThru = "Talk Thru"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .noiseCanceling: "waveform.slash"
        case .ambientAware: "ear"
        case .talkThru: "person.wave.2"
        }
    }
}

struct ContentView: View {
    @Binding var mode: ListeningMode

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ListeningMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Label(option.rawValue, systemImage: option.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(mode == option ? .accentColor : .gray)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(width: 220)
    }
}

#Preview {
    ContentView(mode: .constant(.noiseCanceling))
}

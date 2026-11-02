import Foundation

/// The raw value is the mode's identity only; it is never shown. Use `title` for display.
enum ListeningMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case noiseCanceling = "Noise Canceling"
    case ambientAware = "Ambient Aware"
    case talkThru = "Talk Thru"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .noiseCanceling: "Noise Canceling"
        case .ambientAware: "Ambient Aware"
        case .talkThru: "Talk Thru"
        }
    }

    /// The modes the headphones report with one flag each (in flag order); `off` is all flags cleared.
    static let flagged: [ListeningMode] = [.noiseCanceling, .ambientAware, .talkThru]

    /// Whether the headphones have an adjustable strength for this mode.
    var hasLevel: Bool { self == .noiseCanceling || self == .ambientAware }

    var systemImage: String {
        switch self {
        case .noiseCanceling: "waveform.slash"
        case .ambientAware: "ear"
        case .talkThru: "person.wave.2"
        case .off: "slash.circle"
        }
    }
}

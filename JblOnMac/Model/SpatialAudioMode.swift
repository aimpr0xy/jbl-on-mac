import Foundation

/// Raw values are the mode bytes seen in the JBL app's capture (1, 2, 3 while cycling through
/// the options; 1 was the initial state).
enum SpatialAudioMode: UInt8, CaseIterable, Identifiable {
    case off = 1
    case fixed = 2
    case headTracking = 3

    var id: UInt8 { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .fixed: "Fixed"
        case .headTracking: "Head Tracking"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "slash.circle"
        case .fixed: "person.spatialaudio.stereo.fill"
        case .headTracking: "person.spatialaudio.3d.fill"
        }
    }
}

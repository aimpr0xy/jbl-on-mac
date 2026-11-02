import Foundation

/// The JBL app sends one 8-byte payload per mode. Which payload belongs to which mode was inferred
/// from the order the options were tapped in the capture (the app lists Off, Audio Mode, Video Mode);
/// the payloads are the only thing to change if a mode turns out to be mislabeled.
enum SmartAudioMode: CaseIterable, Identifiable {
    case off
    case audio
    case video

    var id: Self { self }

    var payload: [UInt8] {
        switch self {
        case .off: [0xC5, 0x00, 0x2E, 0x00, 0x18, 0x01, 0xFF, 0xFF]
        case .audio: [0x00, 0x01, 0x2E, 0x00, 0x18, 0x01, 0xFF, 0xFF]
        case .video: [0xC5, 0x00, 0x2E, 0x00, 0x78, 0x00, 0xFF, 0xFF]
        }
    }

    init?(payload: [UInt8]) {
        guard let match = Self.allCases.first(where: { $0.payload == payload }) else { return nil }
        self = match
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .audio: "Audio Mode"
        case .video: "Video Mode"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "slash.circle"
        case .audio: "music.note"
        case .video: "play.rectangle"
        }
    }
}

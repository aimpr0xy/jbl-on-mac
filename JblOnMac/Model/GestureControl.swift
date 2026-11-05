import Foundation

/// An earbud, whose touch control can be set separately.
enum EarbudSide: CaseIterable, Identifiable {
    case left, right

    var id: Self {
        self
    }

    var touchControlsTitle: LocalizedStringResource {
        switch self {
        case .left: "Left Touch Controls"
        case .right: "Right Touch Controls"
        }
    }

    var opposite: EarbudSide {
        self == .left ? .right : .left
    }

    /// The four gesture slots the headphones report and accept for this earbud, as seen in the
    /// JBL app's capture.
    var slots: [UInt8] {
        switch self {
        case .left: [0x06, 0x07, 0x08, 0x0C]
        case .right: [0x09, 0x0A, 0x0B, 0x0E]
        }
    }
}

/// What an earbud's touch controls do. The headphones store one action per slot; these are the
/// four combinations the JBL app offers, so any other combination is unknown.
enum GestureControl: CaseIterable, Identifiable {
    // None comes first, because it is listed first on the screen.
    case none
    case ambientSound
    case volume
    case playback

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .ambientSound: "Ambient Sound Control"
        case .volume: "Volume Control"
        case .playback: "Playback Control"
        case .none: "None"
        }
    }

    var systemImage: String {
        switch self {
        case .ambientSound: "ear.and.waveform"
        case .volume: "speaker.wave.2"
        case .playback: "playpause"
        case .none: "slash.circle"
        }
    }

    /// The action for each of the side's slots. The right earbud's ambient sound control uses a
    /// different first action (0B) than the left one (09).
    func actions(for side: EarbudSide) -> [UInt8] {
        switch self {
        case .ambientSound: [side == .left ? 0x09 : 0x0B, 0x04, 0x00, 0xA1]
        case .volume: [0x01, 0x02, 0x00, 0xA1]
        case .playback: [0x08, 0x05, 0x06, 0xA1]
        case .none: [0x00, 0x00, 0x00, 0x00]
        }
    }

    /// Nil when the actions aren't one of the known combinations. The Tune 230NC uses the left
    /// earbud's actions on both sides, so those are accepted for the right one as well.
    init?(actions: [UInt8], side: EarbudSide) {
        guard let match = Self.allCases.first(where: { $0.actions(for: side) == actions })
            ?? Self.allCases.first(where: { $0.actions(for: .left) == actions }) else { return nil }
        self = match
    }
}

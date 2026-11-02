import Foundation

/// Raw values are the preset ids seen in the JBL app's capture. Gains (dB) for the ten bands
/// and the leading headroom value are copied from what the app sent for each preset.
/// The headphones accept no names, so which id is which preset was inferred from the curves.
enum EqualizerPreset: UInt8, CaseIterable, Identifiable {
    case off = 0
    case studio = 7
    case bass = 3
    case club = 1
    case extremeBass = 9
    case vocal = 2
    case jazz = 6

    var id: UInt8 { rawValue }

    /// Band centre frequencies in Hz, shared by every preset.
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .studio: "Studio"
        case .bass: "Bass"
        case .club: "Club"
        case .extremeBass: "Extreme Bass"
        case .vocal: "Vocal"
        case .jazz: "Jazz"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "slash.circle"
        case .studio: "slider.horizontal.3"
        case .bass: "speaker.wave.2"
        case .club: "sparkles"
        case .extremeBass: "waveform.path"
        case .vocal: "mic"
        case .jazz: "music.quarternote.3"
        }
    }

    /// Gain in dB for each of the ten bands.
    var gains: [Float] {
        switch self {
        case .off: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .studio: [-2, -1, -1, -0.5, 0, 0, 0, 0, 0, 0]
        case .bass: [4, 4, 3, 2.5, 0.5, 0, 0, 0, 0, 0]
        case .club: [4, 3, 1, 2.5, -1.5, -1.5, 0, 1, 3, 4]
        case .extremeBass: [4, 4.5, 4.5, 3.5, -1, 0, 0, 2, 2, 0]
        case .vocal: [-1.5, -3, -3, 1, 3.5, 3.5, 3, 1.5, 0, -1.5]
        case .jazz: [2, 1.5, 1, 0, 0, 0, 0, 1, 1, 2]
        }
    }

    /// Value sent ahead of the bands (as a little-endian float), as captured per preset.
    var headroom: Float {
        switch self {
        case .off, .studio: 0
        case .bass: Float(bitPattern: 0x40ECEDE7)
        case .jazz: Float(bitPattern: 0x4065B853)
        case .club: Float(bitPattern: 0x40C44ADB)
        case .vocal: Float(bitPattern: 0x40D32A08)
        case .extremeBass: Float(bitPattern: 0x410758D1)
        }
    }
}

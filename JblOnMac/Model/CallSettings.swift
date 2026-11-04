import Foundation

/// Raw values are the bytes seen in the capture (0, 1, 2 while cycling); which value is which
/// option was inferred from the order the app lists them.
enum CallSoundSetting: UInt8, CaseIterable, Identifiable {
    case natural = 0
    case increasedTreble = 1
    case increasedBass = 2

    var id: UInt8 {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .natural: "Natural"
        case .increasedTreble: "Increased Treble"
        case .increasedBass: "Increased Bass"
        }
    }

    var systemImage: String {
        switch self {
        case .natural: "waveform"
        case .increasedTreble: "hifispeaker"
        case .increasedBass: "hifispeaker.fill"
        }
    }
}

/// Same inference as `CallSoundSetting`.
enum CallVoiceSetting: UInt8, CaseIterable, Identifiable {
    case natural = 0
    case powerful = 1
    case bright = 2

    var id: UInt8 {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .natural: "Natural"
        case .powerful: "Powerful"
        case .bright: "Bright"
        }
    }

    var systemImage: String {
        switch self {
        case .natural: "mic"
        case .powerful: "mic.fill"
        case .bright: "sparkles"
        }
    }
}

enum VoiceAwareLevel: UInt8, CaseIterable, Identifiable {
    case low = 1
    case mid = 2
    case high = 3

    var id: UInt8 {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .low: "Low"
        case .mid: "Mid"
        case .high: "High"
        }
    }

    var systemImage: String {
        switch self {
        case .low: "speaker.wave.1"
        case .mid: "speaker.wave.2"
        case .high: "speaker.wave.3"
        }
    }
}

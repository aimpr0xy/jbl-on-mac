import Foundation

/// One piece of state decoded from a notification. A single packet can carry several
/// (for example the earbud batteries, or both ambient levels).
enum JBLReply: Equatable {
    enum BatteryPart: Equatable {
        case left, right, chargingCase
    }

    case listeningMode(ListeningMode)
    case noiseCancelingLevel(Int)
    case ambientAwareLevel(Int)
    case spatialAudio(SpatialAudioMode)
    case smartAudio(SmartAudioMode)
    case balance(Int)
    case volumeLimiter(Bool)
    case soundLevelOptimizer(Bool)
    /// Nil when the headphones report a value we don't know.
    case callSound(CallSoundSetting?)
    case callVoice(CallVoiceSetting?)
    case voiceAware(enabled: Bool, level: VoiceAwareLevel?)
    case battery(BatteryPart, percent: Int)

    /// Decodes a notification; unknown or malformed packets give an empty array.
    static func decode(_ bytes: [UInt8]) -> [JBLReply] {
        battery(bytes)
            + spatialAudio(bytes)
            + smartAudio(bytes)
            + balance(bytes)
            + volumeLimiter(bytes)
            + callFeatures(bytes)
            + levels(bytes)
            + listeningMode(bytes)
    }

    /// Call feature replies are `AA 06 <len> 00 02 00 <id> ...`.
    private static func callFeatures(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 9, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02 else { return [] }
        switch bytes[6] {
        case 0x23 where bytes[8] <= 1:
            return [.soundLevelOptimizer(bytes[8] == 1)]
        case 0x14 where bytes.count >= 10:
            return [.callSound(CallSoundSetting(rawValue: bytes[9]))]
        case 0x16 where bytes.count >= 11:
            return [.callVoice(CallVoiceSetting(rawValue: bytes[10]))]
        case 0x0D where bytes.count >= 10 && bytes[8] <= 1:
            return [.voiceAware(enabled: bytes[8] == 1, level: VoiceAwareLevel(rawValue: bytes[9]))]
        default:
            return []
        }
    }

    /// Volume limiter replies are `AA 06 05 00 02 00 20 01 <00|01>`.
    private static func volumeLimiter(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 9, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02,
              bytes[6] == 0x20, bytes[7] == 0x01, bytes[8] <= 1 else { return [] }
        return [.volumeLimiter(bytes[8] == 1)]
    }

    /// Balance replies are `AA A8 05 02 01 <enabled> 02 <100 + balance>`.
    private static func balance(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 8, bytes[0] == 0xAA, bytes[1] == 0xA8, bytes[3] == 0x02,
              bytes[6] == 0x02, (84...116).contains(Int(bytes[7])) else { return [] }
        return [.balance(Int(bytes[7]) - 100)]
    }

    /// Level replies are `AA 91 05 22` followed by `<id> <level>` pairs (04 = noise canceling,
    /// A1 = ambient aware). The mode report `AA 91 09 12 ... 04 <level>` also carries the NC level.
    private static func levels(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 6, bytes[0] == 0xAA, bytes[1] == 0x91 else { return [] }
        var index: Int
        switch bytes[3] {
        case 0x22: index = 4
        case 0x12: index = 10
        default: return []
        }
        var replies: [JBLReply] = []
        while index + 1 < bytes.count {
            let level = Int(bytes[index + 1])
            if (1...7).contains(level) {
                if bytes[index] == 0x04 { replies.append(.noiseCancelingLevel(level)) }
                if bytes[index] == 0xA1 { replies.append(.ambientAwareLevel(level)) }
            }
            index += 2
        }
        return replies
    }

    /// Spatial audio replies are `AA 06 06 00 02 00 0C 02 <00|01> <mode>`.
    private static func spatialAudio(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02,
              bytes[6] == 0x0C, let mode = SpatialAudioMode(rawValue: bytes[9]) else { return [] }
        return [.spatialAudio(mode)]
    }

    /// Smart audio and video replies are `AA 80 09 02` followed by the 8 payload bytes.
    private static func smartAudio(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 12, bytes[0] == 0xAA, bytes[1] == 0x80, bytes[2] == 0x09,
              bytes[3] == 0x02, let mode = SmartAudioMode(payload: Array(bytes[4..<12])) else { return [] }
        return [.smartAudio(mode)]
    }

    /// Battery replies (and later unsolicited updates) are `AA 06 <len> 00 02 00` followed by
    /// entries of `<id> 02 00 <percent>`, optionally separated by a `00` byte.
    private static func battery(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02 else { return [] }
        var replies: [JBLReply] = []
        var index = 6
        while index + 3 < bytes.count {
            let percent = Int(bytes[index + 3])
            if percent <= 100 {
                switch bytes[index] {
                case 0x1A: replies.append(.battery(.left, percent: percent))
                case 0x1B: replies.append(.battery(.right, percent: percent))
                case 0x1C: replies.append(.battery(.chargingCase, percent: percent))
                default: break
                }
            }
            index += 4
            if index < bytes.count, bytes[index] == 0 { index += 1 }
        }
        return replies
    }

    /// The headphones report the active mode as `AA 91 09 12 01 <NC> 02 <Ambient> 03 <TalkThru> 04 07`,
    /// both when asked and after a change.
    private static func listeningMode(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x91, bytes[3] == 0x12 else { return [] }
        let flags = [bytes[5], bytes[7], bytes[9]]
        // All flags cleared means ambient sound control is off.
        return [.listeningMode(flags.firstIndex(of: 1).map { ListeningMode.flagged[$0] } ?? .off)]
    }
}

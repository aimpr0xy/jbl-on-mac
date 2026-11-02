import Foundation

/// A packet sent to the headphones, as observed in the Packet Logger capture of the JBL app:
///   service characteristics  ...6F6D0002 (write)  /  ...6F6D0001 (notify)
///   ambient sound write      AA 91 07 10 | 01 <NC> | 02 <Ambient> | 03 <TalkThru>   (all 0 = off)
///   level write              AA 91 03 20 | <A1 ambient | 04 noise canceling> <1...7>
///   level query              AA 91 01 21 (assumed from the 10/11/12 pattern)
///   battery query            AA 06 05 00 01 00 1A 00 1B  (and AA 06 03 00 01 00 1C)
///   spatial audio write      AA 06 06 00 00 00 0C 02 01 <Mode>
///   spatial audio query      AA 06 03 00 01 00 0C
///   smart audio/video write  AA 80 09 00 | <8 payload bytes, see SmartAudioMode>
///   smart audio/video query  AA 80 01 01
///   balance write            AA A8 05 00 01 01 02 <100 + balance>   (0x54 = -16 left ... 0x74 = +16 right)
///   balance query            AA A8 01 01 (assumed from the other features' query pattern)
///   volume limiter write     AA 06 05 00 00 00 20 01 <00 off | 01 on>
///   volume limiter query     AA 06 03 00 01 00 20 (assumed from the spatial audio query pattern)
///   call features write      AA 06 .. 00 00 00 <id> ...   (queries use AA 06 03 00 01 00 <id>)
///     23  sound level optimizer   AA 06 05 00 00 00 23 01 <00 off | 01 on>
///     14  call sound setting      AA 06 06 00 00 00 14 02 01 <0 natural | 1 treble | 2 bass>
///     16  call voice setting      AA 06 07 00 00 00 16 03 FF FF <0 natural | 1 powerful | 2 bright>
///     0D  voice aware             AA 06 06 00 00 00 0D 02 <00 off | 01 on> <1 low | 2 mid | 3 high>
/// Replies are decoded by `JBLReply`.
enum JBLCommand: Equatable {
    // Writes
    case setListeningMode(ListeningMode)
    /// Strength (1...7) of noise canceling or ambient aware; other modes have no level.
    case setLevel(ListeningMode, Int)
    case setSpatialAudio(SpatialAudioMode)
    case setSmartAudio(SmartAudioMode)
    /// -16 (left) ... 16 (right)
    case setBalance(Int)
    case setVolumeLimiter(Bool)
    case setSoundLevelOptimizer(Bool)
    case setCallSound(CallSoundSetting)
    case setCallVoice(CallVoiceSetting)
    case setVoiceAware(enabled: Bool, level: VoiceAwareLevel)

    // Queries
    case queryListeningMode
    case queryLevels
    case queryEarbudBattery
    case queryCaseBattery
    case querySmartAudio
    case querySpatialAudio
    case queryBalance
    case queryVolumeLimiter
    case queryCallFeature(id: UInt8)

    /// Everything asked for once notifications are on.
    static let initialQueries: [JBLCommand] = [
        .queryListeningMode, .queryLevels, .queryEarbudBattery, .queryCaseBattery,
        .querySmartAudio, .querySpatialAudio, .queryBalance, .queryVolumeLimiter,
        .queryCallFeature(id: 0x23), .queryCallFeature(id: 0x14),
        .queryCallFeature(id: 0x16), .queryCallFeature(id: 0x0D),
    ]

    var bytes: [UInt8] {
        switch self {
        case .setListeningMode(let mode):
            // At most one of the three flags is set to 1; Off clears all of them.
            let flags = ListeningMode.flagged.map { UInt8($0 == mode ? 1 : 0) }
            return [0xAA, 0x91, 0x07, 0x10, 0x01, flags[0], 0x02, flags[1], 0x03, flags[2]]
        case .setLevel(let mode, let level):
            let id: UInt8 = mode == .noiseCanceling ? 0x04 : 0xA1
            return [0xAA, 0x91, 0x03, 0x20, id, UInt8(clamping: level)]
        case .setSpatialAudio(let mode):
            return [0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, 0x0C, 0x02, 0x01, mode.rawValue]
        case .setSmartAudio(let mode):
            return [0xAA, 0x80, 0x09, 0x00] + mode.payload
        case .setBalance(let value):
            return [0xAA, 0xA8, 0x05, 0x00, 0x01, 0x01, 0x02, UInt8(clamping: 100 + value)]
        case .setVolumeLimiter(let enabled):
            return [0xAA, 0x06, 0x05, 0x00, 0x00, 0x00, 0x20, 0x01, enabled ? 1 : 0]
        case .setSoundLevelOptimizer(let enabled):
            return [0xAA, 0x06, 0x05, 0x00, 0x00, 0x00, 0x23, 0x01, enabled ? 1 : 0]
        case .setCallSound(let setting):
            return [0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, 0x14, 0x02, 0x01, setting.rawValue]
        case .setCallVoice(let setting):
            return [0xAA, 0x06, 0x07, 0x00, 0x00, 0x00, 0x16, 0x03, 0xFF, 0xFF, setting.rawValue]
        case .setVoiceAware(let enabled, let level):
            return [0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, 0x0D, 0x02, enabled ? 1 : 0, level.rawValue]

        case .queryListeningMode: return [0xAA, 0x91, 0x01, 0x11]
        case .queryLevels: return [0xAA, 0x91, 0x01, 0x21]
        case .queryEarbudBattery: return [0xAA, 0x06, 0x05, 0x00, 0x01, 0x00, 0x1A, 0x00, 0x1B]
        case .queryCaseBattery: return Self.featureQuery(id: 0x1C)
        case .querySmartAudio: return [0xAA, 0x80, 0x01, 0x01]
        case .querySpatialAudio: return Self.featureQuery(id: 0x0C)
        case .queryBalance: return [0xAA, 0xA8, 0x01, 0x01]
        case .queryVolumeLimiter: return Self.featureQuery(id: 0x20)
        case .queryCallFeature(let id): return Self.featureQuery(id: id)
        }
    }

    private static func featureQuery(id: UInt8) -> [UInt8] {
        [0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, id]
    }
}

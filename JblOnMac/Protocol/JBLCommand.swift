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
///   equalizer write          AA A2 74 00 03 <preset> <headroom f32> 30 00*8 | 10 x (0A 01 <gain f32> <Hz f32>) | 0A
///                            (floats little-endian; the app writes to handle 0x002D, same as the others)
///   equalizer query          AA A2 02 01 FF   (replies with the same frame as a write echo: AA A2 74 00 04 <preset> ...)
///   touch controls write     AA 77 09 00 <slot> <action> x 4   (left slots 06 07 08 0C, right 09 0A 0B 0E; see GestureControl)
///   touch controls query     AA 77 02 01 FF   (both earbuds; FD left only, FE right only)
///
/// The Tune 230NC (see `JBLModel`) shares the ambient sound commands (without levels) and the touch
/// controls query, but speaks its own dialect for the rest:
///   battery query            AA 25 01 00
///   smart audio/video write  AA 81 08 <8 payload bytes, see SmartAudioMode>   (query AA 82 00)
///   voice aware write        AA 98 02 00 <00 off | 01 low | 02 mid | 03 high>   (query AA 98 01 01)
///   status query             AA 11 00   (replies with the name and earbud firmware, see JBLReply)
///   case firmware query      AA 26 01 00
///   touch controls write     AA 77 0B 00 <slot> <action> x 4 <other side's last slot> <action>
///   equalizer write          AA 41 <len> <chunks> | <index> <up to 79 bytes> per chunk | AA 05 41
///                            (each packet waits for the ack AA 00 02 41 00; payload below)
///                            04 00 <headroom f32> 30 00*8 0A 00 00 00 | 10 x (01 00 00 00 <gain f32> <Hz f32> <Q f32>)
///   equalizer query          AA 42 01 01   (replies with a chunked transfer, see `JBLReply`, and every
///                            packet of it is acked with AA 01 02 43 00)
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
    case setEqualizer(EqualizerPreset)
    case setGestureControl(EarbudSide, GestureControl)
    /// Tune 230NC: also carries the other earbud's last slot, as its app always sends it.
    case setGestureControlWithOtherSide(EarbudSide, GestureControl, other: GestureControl)
    /// Tune 230NC: one packet of a chunked equalizer write; see `equalizerUpload(_:)`.
    case startUpload(length: Int, chunks: Int)
    case uploadChunk(index: Int, [UInt8])
    case finishUpload
    /// Tune 230NC: acknowledges one packet of a chunked reply.
    case acknowledgeDownload

    // Queries
    case queryListeningMode
    case queryLevels
    case queryEarbudBattery
    case queryCaseBattery
    case querySmartAudio
    case querySpatialAudio
    case queryBalance
    case queryEqualizer
    case queryVolumeLimiter
    case queryCallFeature(id: UInt8)
    case queryGestureControls
    /// Tune 230NC: the same modes as `setSmartAudio`, in another command group.
    case setTune230NCSmartAudio(SmartAudioMode)
    /// Tune 230NC: nil turns voice aware off.
    case setTune230NCVoiceAware(VoiceAwareLevel?)
    /// Tune 230NC queries.
    case queryBatteryLevels
    case queryEqualizerCurve
    case queryTune230NCSmartAudio
    case queryTune230NCVoiceAware
    case queryStatus
    case queryCaseFirmware

    /// Payload bytes per equalizer upload chunk, after the chunk index.
    static let uploadChunkSize = 79

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
        case .setEqualizer(let preset):
            var packet: [UInt8] = [0xAA, 0xA2, 0x74, 0x00, 0x03, preset.rawValue]
            packet += Self.littleEndian(preset.headroom)
            packet += [0x30] + [UInt8](repeating: 0, count: 8)
            for (gain, frequency) in zip(preset.gains, EqualizerPreset.frequencies) {
                packet += [0x0A, 0x01] + Self.littleEndian(gain) + Self.littleEndian(frequency)
            }
            return packet + [0x0A]
        case .setGestureControl(let side, let control):
            // Slot and action alternate: `<slot> <action> <slot> <action> ...`.
            return [0xAA, 0x77, 0x09, 0x00] + zip(side.slots, control.actions(for: side)).flatMap { [$0, $1] }
        case .setGestureControlWithOtherSide(let side, let control, let other):
            // Both earbuds use the left one's actions on this model, also for ambient sound control.
            let pairs = zip(side.slots, control.actions(for: .left)).flatMap { [$0, $1] }
            let otherSlot = [side.opposite.slots[3], other.actions(for: .left)[3]]
            return [0xAA, 0x77, 0x0B, 0x00] + pairs + otherSlot
        case .startUpload(let length, let chunks):
            return [0xAA, 0x41, UInt8(clamping: length), UInt8(clamping: chunks)]
        case .uploadChunk(let index, let payload):
            return [UInt8(clamping: index)] + payload
        case .finishUpload:
            return [0xAA, 0x05, 0x41]
        case .acknowledgeDownload:
            return [0xAA, 0x01, 0x02, 0x43, 0x00]
        case .setTune230NCSmartAudio(let mode):
            return [0xAA, 0x81, 0x08] + mode.payload
        case .setTune230NCVoiceAware(let level):
            return [0xAA, 0x98, 0x02, 0x00, level?.rawValue ?? 0]

        case .queryListeningMode: return [0xAA, 0x91, 0x01, 0x11]
        case .queryLevels: return [0xAA, 0x91, 0x01, 0x21]
        case .queryEarbudBattery: return [0xAA, 0x06, 0x05, 0x00, 0x01, 0x00, 0x1A, 0x00, 0x1B]
        case .queryCaseBattery: return Self.featureQuery(id: 0x1C)
        case .querySmartAudio: return [0xAA, 0x80, 0x01, 0x01]
        case .querySpatialAudio: return Self.featureQuery(id: 0x0C)
        case .queryBalance: return [0xAA, 0xA8, 0x01, 0x01]
        case .queryEqualizer: return [0xAA, 0xA2, 0x02, 0x01, 0xFF]
        case .queryVolumeLimiter: return Self.featureQuery(id: 0x20)
        case .queryCallFeature(let id): return Self.featureQuery(id: id)
        case .queryGestureControls: return [0xAA, 0x77, 0x02, 0x01, 0xFF]
        case .queryBatteryLevels: return [0xAA, 0x25, 0x01, 0x00]
        case .queryEqualizerCurve: return [0xAA, 0x42, 0x01, 0x01]
        case .queryTune230NCSmartAudio: return [0xAA, 0x82, 0x00]
        case .queryTune230NCVoiceAware: return [0xAA, 0x98, 0x01, 0x01]
        case .queryStatus: return [0xAA, 0x11, 0x00]
        case .queryCaseFirmware: return [0xAA, 0x26, 0x01, 0x00]
        }
    }

    /// The query that makes the headphones report the state this write changes, so the real value
    /// can be restored if the write fails. Nil for queries and for writes that have no query.
    var refreshQuery: JBLCommand? {
        switch self {
        case .setListeningMode: return .queryListeningMode
        case .setLevel: return .queryLevels
        case .setSpatialAudio: return .querySpatialAudio
        case .setSmartAudio: return .querySmartAudio
        case .setBalance: return .queryBalance
        case .setVolumeLimiter: return .queryVolumeLimiter
        case .setSoundLevelOptimizer: return .queryCallFeature(id: 0x23)
        case .setCallSound: return .queryCallFeature(id: 0x14)
        case .setCallVoice: return .queryCallFeature(id: 0x16)
        case .setVoiceAware: return .queryCallFeature(id: 0x0D)
        case .setEqualizer: return .queryEqualizer
        case .setGestureControl, .setGestureControlWithOtherSide: return .queryGestureControls
        case .startUpload, .uploadChunk, .finishUpload: return .queryEqualizerCurve
        case .setTune230NCSmartAudio: return .queryTune230NCSmartAudio
        case .setTune230NCVoiceAware: return .queryTune230NCVoiceAware
        case .acknowledgeDownload, .queryListeningMode, .queryLevels, .queryEarbudBattery,
             .queryCaseBattery, .querySmartAudio, .querySpatialAudio, .queryBalance,
             .queryEqualizer, .queryVolumeLimiter, .queryCallFeature, .queryGestureControls,
             .queryBatteryLevels, .queryEqualizerCurve, .queryTune230NCSmartAudio,
             .queryTune230NCVoiceAware, .queryStatus, .queryCaseFirmware:
            return nil
        }
    }

    /// Tune 230NC: the packets that write a preset, in order. Its app always sends preset id 00
    /// followed by the whole curve.
    static func equalizerUpload(_ preset: EqualizerPreset) -> [JBLCommand] {
        var payload: [UInt8] = [0x04, 0x00] + littleEndian(preset.tune230NCHeadroom)
        payload += [0x30] + [UInt8](repeating: 0, count: 8) + [0x0A, 0x00, 0x00, 0x00]
        for (gain, frequency) in zip(preset.tune230NCGains, EqualizerPreset.frequencies) {
            payload += [0x01, 0x00, 0x00, 0x00] + littleEndian(gain) + littleEndian(frequency) + littleEndian(1)
        }
        let chunks = stride(from: 0, to: payload.count, by: uploadChunkSize).map {
            Array(payload[$0..<min($0 + uploadChunkSize, payload.count)])
        }
        return [.startUpload(length: payload.count, chunks: chunks.count)]
            + chunks.enumerated().map { .uploadChunk(index: $0.offset, $0.element) }
            + [.finishUpload]
    }

    private static func littleEndian(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    private static func featureQuery(id: UInt8) -> [UInt8] {
        [0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, id]
    }
}

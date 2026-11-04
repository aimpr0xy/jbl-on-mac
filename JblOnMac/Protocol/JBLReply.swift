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
    case equalizer(EqualizerPreset)
    /// Nil when the earbud reports a combination of actions we don't know.
    case gestureControl(EarbudSide, GestureControl?)
    /// Tune 230NC: `AA 00 02 <command group> <status>`, sent for each packet of an upload and for
    /// some writes.
    case acknowledged(group: UInt8, status: UInt8)
    /// Tune 230NC: `AA 43 <length> <chunks>` starts a chunked reply. The chunks follow as raw
    /// `<index> <bytes…>` notifications and `AA 04 43` ends it; see `equalizerGains(fromDownload:)`.
    case downloadStarted(length: Int, chunks: Int)
    case downloadFinished
    /// Tune 230NC: earbud and charging case firmware versions, e.g. "3.7.0".
    case firmware(String)
    case caseFirmware(String)

    /// Decodes a notification, which may carry several frames back to back; unknown or malformed
    /// frames give nothing. Decoding stops at the first frame that is cut short or doesn't start
    /// with `AA`, because without a valid length there is no telling where the next one begins.
    static func decode(_ bytes: [UInt8]) -> [JBLReply] {
        var replies: [JBLReply] = []
        var start = 0
        while let length = frameLength(in: bytes, at: start) {
            replies += decode(frame: Array(bytes[start ..< start + length]))
            start += length
        }
        return replies
    }

    /// Frames are `AA <group> <len> <payload…>`. The length byte counts everything after itself in
    /// groups `91`, `80` and `A8`, but is one short in groups `06` and `A2` (as seen in every
    /// documented capture, e.g. `AA 06 06 00 00 00 0C 02 01 03` is 10 bytes), so those frames
    /// are `len + 4` bytes long and the others `len + 3`. The Tune 230NC's download frames have no
    /// length byte: `AA 43` carries the transfer's length instead and `AA 04 43` is 3 bytes.
    /// Nil when there is no complete frame.
    private static func frameLength(in bytes: [UInt8], at start: Int) -> Int? {
        guard bytes.count - start >= 3, bytes[start] == 0xAA else { return nil }
        if bytes[start + 1] == 0x04 {
            return 3
        }
        guard bytes.count - start >= 4 else { return nil }
        if bytes[start + 1] == 0x43 {
            return 4
        }
        let overhead = (bytes[start + 1] == 0x06 || bytes[start + 1] == 0xA2) ? 4 : 3
        let length = Int(bytes[start + 2]) + overhead
        return start + length <= bytes.count ? length : nil
    }

    /// Picks the one decoder that owns a frame, so decoders can't match each other's packets.
    private static func decode(frame bytes: [UInt8]) -> [JBLReply] {
        switch bytes[1] {
        case 0x06: decodeFeature(frame: bytes)
        case 0x91: bytes[3] == 0x12 ? levels(bytes) + listeningMode(bytes) : levels(bytes)
        case 0x00, 0x04, 0x43: decodeTransfer(frame: bytes)
        case 0xA2, 0x77, 0xA8, 0x25: decodeSetting(frame: bytes)
        default: decodeDevice(frame: bytes)
        }
    }

    private static func decodeSetting(frame bytes: [UInt8]) -> [JBLReply] {
        switch bytes[1] {
        case 0xA2: equalizer(bytes)
        case 0x77: gestureControls(bytes)
        case 0xA8: balance(bytes)
        case 0x25: batteryLevels(bytes)
        default: []
        }
    }

    private static func decodeDevice(frame bytes: [UInt8]) -> [JBLReply] {
        switch bytes[1] {
        case 0x83: tune230NCSmartAudio(bytes)
        case 0x98: tune230NCVoiceAware(bytes)
        case 0x12: status(bytes)
        case 0x26: caseFirmware(bytes)
        case 0x80: smartAudio(bytes)
        default: []
        }
    }

    /// Acknowledgements and the chunked downloads of the Tune 230NC.
    private static func decodeTransfer(frame bytes: [UInt8]) -> [JBLReply] {
        switch bytes[1] {
        case 0x00 where bytes.count >= 5: [.acknowledged(group: bytes[3], status: bytes[4])]
        case 0x43: [.downloadStarted(length: Int(bytes[2]), chunks: Int(bytes[3]))]
        case 0x04 where bytes[2] == 0x43: [.downloadFinished]
        default: []
        }
    }

    /// Group `06` carries several features, told apart by the id in byte 6.
    private static func decodeFeature(frame bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 7 else { return [] }
        switch bytes[6] {
        case 0x0C: return spatialAudio(bytes)
        case 0x20: return volumeLimiter(bytes)
        case 0x23, 0x14, 0x16, 0x0D: return callFeatures(bytes)
        // Battery entries are `<id> 02 00 <percent>` with ids 1A, 1B and 1C in any order.
        default: return battery(bytes)
        }
    }

    /// Equalizer replies echo the write: `AA A2 74 00 04 <preset> ...`.
    private static func equalizer(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 6, bytes[0] == 0xAA, bytes[1] == 0xA2, bytes[4] == 0x04,
              let preset = EqualizerPreset(rawValue: bytes[5]) else { return [] }
        return [.equalizer(preset)]
    }

    /// Touch control replies are `AA 77 <len> 02` followed by `<slot> <action>` pairs, four per
    /// earbud; a reply covers one or both earbuds. Echoes of a write (`00` instead of `02`) are ignored.
    private static func gestureControls(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 4, bytes[0] == 0xAA, bytes[1] == 0x77, bytes[3] == 0x02 else { return [] }
        var actions: [UInt8: UInt8] = [:]
        var index = 4
        while index + 1 < bytes.count {
            actions[bytes[index]] = bytes[index + 1]
            index += 2
        }
        return EarbudSide.allCases.compactMap { side in
            let values = side.slots.compactMap { actions[$0] }
            guard values.count == side.slots.count else { return nil }
            return .gestureControl(side, GestureControl(actions: values, side: side))
        }
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
              bytes[6] == 0x02, (84 ... 116).contains(Int(bytes[7])) else { return [] }
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
            if (1 ... 7).contains(level) {
                if bytes[index] == 0x04 {
                    replies.append(.noiseCancelingLevel(level))
                }
                if bytes[index] == 0xA1 {
                    replies.append(.ambientAwareLevel(level))
                }
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
              bytes[3] == 0x02, let mode = SmartAudioMode(payload: Array(bytes[4 ..< 12])) else { return [] }
        return [.smartAudio(mode)]
    }

    /// Tune 230NC battery replies (and later unsolicited updates) are
    /// `AA 25 0D 01 00 00 <left> <right> 00 <case> <mV LE16> <mV LE16> 54 00`. The case byte read
    /// 2 while the JBL app showed the case at 2%; what the `00` before it and the trailing `54`
    /// mean is unknown.
    private static func batteryLevels(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 8, bytes[3] == 0x01 else { return [] }
        var parts: [(BatteryPart, UInt8)] = [(.left, bytes[6]), (.right, bytes[7])]
        if bytes.count >= 10 {
            parts.append((.chargingCase, bytes[9]))
        }
        return parts.compactMap { part, percent in
            percent <= 100 ? .battery(part, percent: Int(percent)) : nil
        }
    }

    /// Tune 230NC smart audio and video replies are `AA 83 08` followed by the 8 payload bytes.
    private static func tune230NCSmartAudio(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 11, bytes[2] == 0x08,
              let mode = SmartAudioMode(payload: Array(bytes[3 ..< 11])) else { return [] }
        return [.smartAudio(mode)]
    }

    /// Tune 230NC voice aware replies are `AA 98 02 02 <00 off | 01 low | 02 mid | 03 high>`;
    /// echoes of a write (`00` instead of `02`) are ignored.
    private static func tune230NCVoiceAware(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 5, bytes[3] == 0x02, bytes[4] <= 3 else { return [] }
        return [.voiceAware(enabled: bytes[4] != 0, level: VoiceAwareLevel(rawValue: bytes[4]))]
    }

    /// Tune 230NC status replies are `AA 12 25 <name, 16 bytes> <10 bytes> <firmware major minor
    /// patch> …`, e.g. `03 07 00` for 3.7.0.
    private static func status(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 32, bytes[2] == 0x25 else { return [] }
        return [.firmware(version(bytes[29 ..< 32]))]
    }

    /// Tune 230NC case firmware replies are `AA 26 04 01 <major> <minor> <patch>`.
    private static func caseFirmware(_ bytes: [UInt8]) -> [JBLReply] {
        guard bytes.count >= 7, bytes[2] == 0x04 else { return [] }
        return [.caseFirmware(version(bytes[4 ..< 7]))]
    }

    private static func version(_ parts: ArraySlice<UInt8>) -> String {
        parts.map(String.init).joined(separator: ".")
    }

    /// Tune 230NC: the ten band gains of an equalizer download, given the chunks' bytes without
    /// their index. The payload is `04 01 00 <f32> <f32> <band count u32>` followed by bands of
    /// `01 00 00 00 <gain f32> <Hz f32> <Q f32>`. Nil if it isn't a ten-band curve.
    static func equalizerGains(fromDownload payload: [UInt8]) -> [Float]? {
        let header = 15, band = 16
        guard payload.count >= header, payload[0] == 0x04, payload[11] == 10,
              payload.count >= header + 10 * band else { return nil }
        return (0 ..< 10).map { index in
            let start = header + index * band + 4
            let bits = payload[start ..< start + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return Float(bitPattern: bits)
        }
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
            if index < bytes.count, bytes[index] == 0 {
                index += 1
            }
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

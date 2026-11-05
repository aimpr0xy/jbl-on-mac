@testable import JblOnMac
import Testing

/// The Tune Beam 2 dialect. Expected packets are the ones documented at the top of
/// `JBLCommand.swift`, copied from the PacketLogger capture of the JBL app talking to a Tune Beam 2.
struct TuneBeam2Tests {
    struct Case: CustomTestStringConvertible {
        let command: JBLCommand
        let hex: String
        var testDescription: String {
            "\(command)"
        }
    }

    nonisolated static let writes: [Case] = [
        Case(command: .setListeningMode(.off), hex: "AA 91 07 10 01 00 02 00 03 00"),
        Case(command: .setListeningMode(.noiseCanceling), hex: "AA 91 07 10 01 01 02 00 03 00"),
        Case(command: .setListeningMode(.ambientAware), hex: "AA 91 07 10 01 00 02 01 03 00"),
        Case(command: .setListeningMode(.talkThru), hex: "AA 91 07 10 01 00 02 00 03 01"),
        Case(command: .setLevel(.noiseCanceling, 5), hex: "AA 91 03 20 04 05"),
        Case(command: .setLevel(.ambientAware, 7), hex: "AA 91 03 20 A1 07"),
        Case(command: .setSpatialAudio(.off), hex: "AA 06 06 00 00 00 0C 02 01 01"),
        Case(command: .setSpatialAudio(.headTracking), hex: "AA 06 06 00 00 00 0C 02 01 03"),
        Case(command: .setSmartAudio(.off), hex: "AA 80 09 00 C5 00 2E 00 18 01 FF FF"),
        Case(command: .setSmartAudio(.audio), hex: "AA 80 09 00 00 01 2E 00 18 01 FF FF"),
        Case(command: .setSmartAudio(.video), hex: "AA 80 09 00 C5 00 2E 00 78 00 FF FF"),
        Case(command: .setBalance(-16), hex: "AA A8 05 00 01 01 02 54"),
        Case(command: .setBalance(0), hex: "AA A8 05 00 01 01 02 64"),
        Case(command: .setBalance(16), hex: "AA A8 05 00 01 01 02 74"),
        Case(command: .setVolumeLimiter(false), hex: "AA 06 05 00 00 00 20 01 00"),
        Case(command: .setVolumeLimiter(true), hex: "AA 06 05 00 00 00 20 01 01"),
        Case(command: .setSoundLevelOptimizer(false), hex: "AA 06 05 00 00 00 23 01 00"),
        Case(command: .setSoundLevelOptimizer(true), hex: "AA 06 05 00 00 00 23 01 01"),
        Case(command: .setCallSound(.natural), hex: "AA 06 06 00 00 00 14 02 01 00"),
        Case(command: .setCallSound(.increasedBass), hex: "AA 06 06 00 00 00 14 02 01 02"),
        Case(command: .setCallVoice(.natural), hex: "AA 06 07 00 00 00 16 03 FF FF 00"),
        Case(command: .setCallVoice(.bright), hex: "AA 06 07 00 00 00 16 03 FF FF 02"),
        Case(command: .setVoiceAware(enabled: false, level: .low), hex: "AA 06 06 00 00 00 0D 02 00 01"),
        Case(command: .setVoiceAware(enabled: true, level: .high), hex: "AA 06 06 00 00 00 0D 02 01 03"),
        Case(command: .setGestureControl(.left, .playback), hex: "AA 77 09 00 06 08 07 05 08 06 0C A1"),
        Case(command: .setGestureControl(.left, .volume), hex: "AA 77 09 00 06 01 07 02 08 00 0C A1"),
        Case(command: .setGestureControl(.left, .none), hex: "AA 77 09 00 06 00 07 00 08 00 0C 00"),
        Case(command: .setGestureControl(.left, .ambientSound), hex: "AA 77 09 00 06 09 07 04 08 00 0C A1"),
        Case(command: .setGestureControl(.right, .ambientSound), hex: "AA 77 09 00 09 0B 0A 04 0B 00 0E A1"),
        Case(command: .setGestureControl(.right, .playback), hex: "AA 77 09 00 09 08 0A 05 0B 06 0E A1"),
        Case(command: .setGestureControl(.right, .volume), hex: "AA 77 09 00 09 01 0A 02 0B 00 0E A1"),
        Case(command: .setGestureControl(.right, .none), hex: "AA 77 09 00 09 00 0A 00 0B 00 0E 00")
    ]

    nonisolated static let queries: [Case] = [
        Case(command: .queryListeningMode, hex: "AA 91 01 11"),
        Case(command: .queryLevels, hex: "AA 91 01 21"),
        Case(command: .queryEarbudBattery, hex: "AA 06 05 00 01 00 1A 00 1B"),
        Case(command: .queryCaseBattery, hex: "AA 06 03 00 01 00 1C"),
        Case(command: .querySmartAudio, hex: "AA 80 01 01"),
        Case(command: .querySpatialAudio, hex: "AA 06 03 00 01 00 0C"),
        Case(command: .queryBalance, hex: "AA A8 01 01"),
        Case(command: .queryEqualizer, hex: "AA A2 02 01 FF"),
        Case(command: .queryVolumeLimiter, hex: "AA 06 03 00 01 00 20"),
        Case(command: .queryCallFeature(id: 0x14), hex: "AA 06 03 00 01 00 14"),
        Case(command: .queryGestureControls, hex: "AA 77 02 01 FF")
    ]

    @Test(arguments: writes)
    func writeBytes(_ testCase: Case) {
        #expect(testCase.command.bytes == bytes(testCase.hex))
    }

    @Test(arguments: queries)
    func queryBytes(_ testCase: Case) {
        #expect(testCase.command.bytes == bytes(testCase.hex))
    }

    @Test func levelIsClampedToAByte() {
        #expect(JBLCommand.setLevel(.noiseCanceling, 1000).bytes.last == 0xFF)
    }

    /// The equalizer packet is `AA A2 74 00 03 <preset> <headroom f32> 30 00*8 | 10 x (0A 01 <gain f32> <Hz f32>) |
    /// 0A`.
    @Test(arguments: EqualizerPreset.allCases)
    func equalizerLayout(_ preset: EqualizerPreset) {
        let packet = JBLCommand.setEqualizer(preset).bytes
        #expect(packet.count == 6 + 4 + 9 + 10 * 10 + 1)
        #expect(Array(packet.prefix(6)) == [0xAA, 0xA2, 0x74, 0x00, 0x03, preset.rawValue])
        #expect(Array(packet[10 ..< 19]) == [0x30] + [UInt8](repeating: 0, count: 8))
        for band in 0 ..< 10 {
            let start = 19 + band * 10
            #expect(Array(packet[start ..< start + 2]) == [0x0A, 0x01])
        }
        #expect(packet.last == 0x0A)
    }

    @Test func writesRefreshWithTheMatchingQuery() {
        #expect(JBLCommand.setBalance(3).refreshQuery == .queryBalance)
        #expect(JBLCommand.setVoiceAware(enabled: true, level: .mid).refreshQuery == .queryCallFeature(id: 0x0D))
        #expect(JBLCommand.setEqualizer(.bass).refreshQuery == .queryEqualizer)
    }

    // MARK: - Replies

    nonisolated static let decoded: [ReplyCase] = [
        ReplyCase(name: "equalizer", hex: equalizerFrame(preset: "03"), replies: [.equalizer(.bass)]),
        ReplyCase(name: "earbud batteries",
                  hex: "AA 06 0B 00 02 00 1A 02 00 50 00 1B 02 00 4B",
                  replies: [.battery(.left, percent: 80), .battery(.right, percent: 75)]),
        ReplyCase(name: "case battery", hex: "AA 06 06 00 02 00 1C 02 00 64",
                  replies: [.battery(.chargingCase, percent: 100)]),
        ReplyCase(name: "battery above 100% is ignored", hex: "AA 06 06 00 02 00 1C 02 00 65", replies: []),
        ReplyCase(name: "spatial audio", hex: "AA 06 06 00 02 00 0C 02 01 03", replies: [.spatialAudio(.headTracking)]),
        ReplyCase(name: "touch controls, both earbuds",
                  hex: "AA 77 11 02 06 09 07 04 08 00 0C A1 09 01 0A 02 0B 00 0E A1",
                  replies: [.gestureControl(.left, .ambientSound), .gestureControl(.right, .volume)]),
        ReplyCase(name: "touch controls, left only", hex: "AA 77 09 02 06 08 07 05 08 06 0C A1",
                  replies: [.gestureControl(.left, .playback)]),
        ReplyCase(name: "touch controls, right ambient sound", hex: "AA 77 09 02 09 0B 0A 04 0B 00 0E A1",
                  replies: [.gestureControl(.right, .ambientSound)]),
        ReplyCase(name: "touch controls, none", hex: "AA 77 09 02 09 00 0A 00 0B 00 0E 00",
                  replies: [.gestureControl(.right, GestureControl.none)]),
        ReplyCase(name: "touch controls, unknown combination", hex: "AA 77 09 02 06 05 07 05 08 05 0C 05",
                  replies: [.gestureControl(.left, nil)]),
        ReplyCase(
            name: "touch controls write echo is ignored",
            hex: "AA 77 09 00 06 01 07 02 08 00 0C A1",
            replies: []
        ),
        ReplyCase(name: "truncated touch controls", hex: "AA 77 09 02 06 01 07 02 08 00", replies: []),
        ReplyCase(name: "smart audio", hex: "AA 80 09 02 00 01 2E 00 18 01 FF FF", replies: [.smartAudio(.audio)]),
        ReplyCase(name: "balance left", hex: "AA A8 05 02 01 01 02 54", replies: [.balance(-16)]),
        ReplyCase(name: "balance centre", hex: "AA A8 05 02 01 01 02 64", replies: [.balance(0)]),
        ReplyCase(name: "balance right", hex: "AA A8 05 02 01 01 02 74", replies: [.balance(16)]),
        ReplyCase(name: "balance out of range", hex: "AA A8 05 02 01 01 02 75", replies: []),
        ReplyCase(name: "volume limiter on", hex: "AA 06 05 00 02 00 20 01 01", replies: [.volumeLimiter(true)]),
        ReplyCase(name: "volume limiter off", hex: "AA 06 05 00 02 00 20 01 00", replies: [.volumeLimiter(false)]),
        ReplyCase(name: "volume limiter invalid flag", hex: "AA 06 05 00 02 00 20 01 02", replies: []),
        ReplyCase(
            name: "sound level optimizer",
            hex: "AA 06 05 00 02 00 23 01 01",
            replies: [.soundLevelOptimizer(true)]
        ),
        ReplyCase(name: "call sound", hex: "AA 06 06 00 02 00 14 02 01 02", replies: [.callSound(.increasedBass)]),
        ReplyCase(name: "call sound unknown value", hex: "AA 06 06 00 02 00 14 02 01 09", replies: [.callSound(nil)]),
        ReplyCase(name: "call voice", hex: "AA 06 07 00 02 00 16 03 FF FF 01", replies: [.callVoice(.powerful)]),
        ReplyCase(name: "voice aware", hex: "AA 06 06 00 02 00 0D 02 01 02",
                  replies: [.voiceAware(enabled: true, level: .mid)]),
        ReplyCase(name: "levels", hex: "AA 91 05 22 04 05 A1 03",
                  replies: [.noiseCancelingLevel(5), .ambientAwareLevel(3)]),
        ReplyCase(name: "level out of range", hex: "AA 91 03 22 04 08", replies: []),
        ReplyCase(name: "mode: noise canceling",
                  hex: "AA 91 09 12 01 01 02 00 03 00 04 07",
                  replies: [.noiseCancelingLevel(7), .listeningMode(.noiseCanceling)]),
        ReplyCase(name: "mode: ambient aware",
                  hex: "AA 91 09 12 01 00 02 01 03 00 04 02",
                  replies: [.noiseCancelingLevel(2), .listeningMode(.ambientAware)]),
        ReplyCase(name: "mode: talk thru",
                  hex: "AA 91 09 12 01 00 02 00 03 01 04 02",
                  replies: [.noiseCancelingLevel(2), .listeningMode(.talkThru)]),
        ReplyCase(name: "mode: off",
                  hex: "AA 91 09 12 01 00 02 00 03 00 04 02",
                  replies: [.noiseCancelingLevel(2), .listeningMode(.off)])
    ]

    /// Packets that must decode to nothing: unknown ids or values, or cut short.
    nonisolated static let ignored: [ReplyCase] = [
        ReplyCase(name: "unknown feature id", hex: "AA 06 05 00 02 00 7F 01 01", replies: []),
        ReplyCase(name: "unknown equalizer preset", hex: equalizerFrame(preset: "FF"), replies: []),
        ReplyCase(name: "smart audio with unknown payload", hex: "AA 80 09 02 01 02 03 04 05 06 07 08", replies: []),
        ReplyCase(name: "truncated equalizer", hex: "AA A2 74 00 04", replies: []),
        ReplyCase(name: "truncated battery", hex: "AA 06 05 00 02 00 1A 02 00", replies: []),
        ReplyCase(name: "truncated spatial audio", hex: "AA 06 06 00 02 00 0C 02 01", replies: []),
        ReplyCase(name: "truncated smart audio", hex: "AA 80 09 02 00 01 2E 00", replies: []),
        ReplyCase(name: "truncated balance", hex: "AA A8 05 02 01 01 02", replies: []),
        ReplyCase(name: "truncated volume limiter", hex: "AA 06 05 00 02 00 20 01", replies: []),
        ReplyCase(name: "truncated call voice", hex: "AA 06 07 00 02 00 16 03 FF FF", replies: []),
        ReplyCase(name: "truncated mode", hex: "AA 91 09 12 01 01", replies: []),
        ReplyCase(name: "truncated levels", hex: "AA 91 05 22", replies: [])
    ]

    /// A full-length equalizer reply: `AA A2 74 00 04 <preset>` padded to the 120 bytes its length byte promises.
    nonisolated static func equalizerFrame(preset: String) -> String {
        "AA A2 74 00 04 \(preset)" + String(repeating: " 00", count: 114)
    }

    @Test(arguments: decoded)
    func decodes(_ testCase: ReplyCase) {
        #expect(JBLReply.decode(bytes(testCase.hex)) == testCase.replies)
    }

    @Test(arguments: ignored)
    func ignoresMalformedPackets(_ testCase: ReplyCase) {
        #expect(JBLReply.decode(bytes(testCase.hex)).isEmpty)
    }

    /// No prefix of any valid packet may crash the decoder.
    @Test(arguments: decoded)
    func survivesEveryTruncation(_ testCase: ReplyCase) {
        let packet = bytes(testCase.hex)
        for length in 0 ... packet.count {
            _ = JBLReply.decode(Array(packet.prefix(length)))
        }
    }
}

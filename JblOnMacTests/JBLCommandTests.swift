import Testing
@testable import JblOnMac

/// Expected packets are the ones documented at the top of `JBLCommand.swift`.
struct JBLCommandTests {
    struct Case: CustomTestStringConvertible {
        let command: JBLCommand
        let hex: String
        var testDescription: String { "\(command)" }
    }

    static let writes: [Case] = [
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
        Case(command: .setGestureControl(.left, .playback), hex: "AA 77 09 00 06 01 07 02 08 00 0C A1"),
        Case(command: .setGestureControl(.left, .volume), hex: "AA 77 09 00 06 08 07 05 08 06 0C A1"),
        Case(command: .setGestureControl(.left, .none), hex: "AA 77 09 00 06 00 07 00 08 00 0C 00"),
        Case(command: .setGestureControl(.left, .ambientSound), hex: "AA 77 09 00 06 09 07 04 08 00 0C A1"),
        Case(command: .setGestureControl(.right, .ambientSound), hex: "AA 77 09 00 09 0B 0A 04 0B 00 0E A1"),
        Case(command: .setGestureControl(.right, .playback), hex: "AA 77 09 00 09 01 0A 02 0B 00 0E A1"),
        Case(command: .setGestureControl(.right, .volume), hex: "AA 77 09 00 09 08 0A 05 0B 06 0E A1"),
        Case(command: .setGestureControl(.right, .none), hex: "AA 77 09 00 09 00 0A 00 0B 00 0E 00"),
    ]

    static let queries: [Case] = [
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
        Case(command: .queryGestureControls, hex: "AA 77 02 01 FF"),
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

    /// The equalizer packet is `AA A2 74 00 03 <preset> <headroom f32> 30 00*8 | 10 x (0A 01 <gain f32> <Hz f32>) | 0A`.
    @Test(arguments: EqualizerPreset.allCases)
    func equalizerLayout(_ preset: EqualizerPreset) {
        let packet = JBLCommand.setEqualizer(preset).bytes
        #expect(packet.count == 6 + 4 + 9 + 10 * 10 + 1)
        #expect(Array(packet.prefix(6)) == [0xAA, 0xA2, 0x74, 0x00, 0x03, preset.rawValue])
        #expect(Array(packet[10..<19]) == [0x30] + [UInt8](repeating: 0, count: 8))
        for band in 0..<10 {
            let start = 19 + band * 10
            #expect(Array(packet[start..<start + 2]) == [0x0A, 0x01])
        }
        #expect(packet.last == 0x0A)
    }

    @Test func everyInitialQueryIsAQuery() {
        for query in JBLCommand.initialQueries {
            #expect(query.refreshQuery == nil)
        }
    }

    @Test func writesRefreshWithTheMatchingQuery() {
        #expect(JBLCommand.setBalance(3).refreshQuery == .queryBalance)
        #expect(JBLCommand.setVoiceAware(enabled: true, level: .mid).refreshQuery == .queryCallFeature(id: 0x0D))
        #expect(JBLCommand.setEqualizer(.bass).refreshQuery == .queryEqualizer)
    }
}

import Testing
@testable import JblOnMac

struct JBLReplyTests {
    struct Case: CustomTestStringConvertible {
        let name: String
        let hex: String
        let replies: [JBLReply]
        var testDescription: String { name }
    }

    static let decoded: [Case] = [
        Case(name: "equalizer", hex: equalizerFrame(preset: "03"), replies: [.equalizer(.bass)]),
        Case(name: "earbud batteries",
             hex: "AA 06 0B 00 02 00 1A 02 00 50 00 1B 02 00 4B",
             replies: [.battery(.left, percent: 80), .battery(.right, percent: 75)]),
        Case(name: "case battery", hex: "AA 06 06 00 02 00 1C 02 00 64",
             replies: [.battery(.chargingCase, percent: 100)]),
        Case(name: "battery above 100% is ignored", hex: "AA 06 06 00 02 00 1C 02 00 65", replies: []),
        Case(name: "spatial audio", hex: "AA 06 06 00 02 00 0C 02 01 03", replies: [.spatialAudio(.headTracking)]),
        Case(name: "touch controls, both earbuds",
             hex: "AA 77 11 02 06 09 07 04 08 00 0C A1 09 08 0A 05 0B 06 0E A1",
             replies: [.gestureControl(.left, .ambientSound), .gestureControl(.right, .volume)]),
        Case(name: "touch controls, left only", hex: "AA 77 09 02 06 01 07 02 08 00 0C A1",
             replies: [.gestureControl(.left, .playback)]),
        Case(name: "touch controls, right ambient sound", hex: "AA 77 09 02 09 0B 0A 04 0B 00 0E A1",
             replies: [.gestureControl(.right, .ambientSound)]),
        Case(name: "touch controls, none", hex: "AA 77 09 02 09 00 0A 00 0B 00 0E 00",
             replies: [.gestureControl(.right, GestureControl.none)]),
        Case(name: "touch controls, unknown combination", hex: "AA 77 09 02 06 05 07 05 08 05 0C 05",
             replies: [.gestureControl(.left, nil)]),
        Case(name: "touch controls write echo is ignored", hex: "AA 77 09 00 06 01 07 02 08 00 0C A1", replies: []),
        Case(name: "truncated touch controls", hex: "AA 77 09 02 06 01 07 02 08 00", replies: []),
        Case(name: "smart audio", hex: "AA 80 09 02 00 01 2E 00 18 01 FF FF", replies: [.smartAudio(.audio)]),
        Case(name: "balance left", hex: "AA A8 05 02 01 01 02 54", replies: [.balance(-16)]),
        Case(name: "balance centre", hex: "AA A8 05 02 01 01 02 64", replies: [.balance(0)]),
        Case(name: "balance right", hex: "AA A8 05 02 01 01 02 74", replies: [.balance(16)]),
        Case(name: "balance out of range", hex: "AA A8 05 02 01 01 02 75", replies: []),
        Case(name: "volume limiter on", hex: "AA 06 05 00 02 00 20 01 01", replies: [.volumeLimiter(true)]),
        Case(name: "volume limiter off", hex: "AA 06 05 00 02 00 20 01 00", replies: [.volumeLimiter(false)]),
        Case(name: "volume limiter invalid flag", hex: "AA 06 05 00 02 00 20 01 02", replies: []),
        Case(name: "sound level optimizer", hex: "AA 06 05 00 02 00 23 01 01", replies: [.soundLevelOptimizer(true)]),
        Case(name: "call sound", hex: "AA 06 06 00 02 00 14 02 01 02", replies: [.callSound(.increasedBass)]),
        Case(name: "call sound unknown value", hex: "AA 06 06 00 02 00 14 02 01 09", replies: [.callSound(nil)]),
        Case(name: "call voice", hex: "AA 06 07 00 02 00 16 03 FF FF 01", replies: [.callVoice(.powerful)]),
        Case(name: "voice aware", hex: "AA 06 06 00 02 00 0D 02 01 02",
             replies: [.voiceAware(enabled: true, level: .mid)]),
        Case(name: "levels", hex: "AA 91 05 22 04 05 A1 03",
             replies: [.noiseCancelingLevel(5), .ambientAwareLevel(3)]),
        Case(name: "level out of range", hex: "AA 91 03 22 04 08", replies: []),
        Case(name: "mode: noise canceling",
             hex: "AA 91 09 12 01 01 02 00 03 00 04 07",
             replies: [.noiseCancelingLevel(7), .listeningMode(.noiseCanceling)]),
        Case(name: "mode: ambient aware",
             hex: "AA 91 09 12 01 00 02 01 03 00 04 02",
             replies: [.noiseCancelingLevel(2), .listeningMode(.ambientAware)]),
        Case(name: "mode: talk thru",
             hex: "AA 91 09 12 01 00 02 00 03 01 04 02",
             replies: [.noiseCancelingLevel(2), .listeningMode(.talkThru)]),
        Case(name: "mode: off",
             hex: "AA 91 09 12 01 00 02 00 03 00 04 02",
             replies: [.noiseCancelingLevel(2), .listeningMode(.off)]),
    ]

    /// Packets that must decode to nothing: empty, wrong header, unknown, or cut short.
    static let ignored: [Case] = [
        Case(name: "empty", hex: "", replies: []),
        Case(name: "header only", hex: "AA", replies: []),
        Case(name: "wrong start byte", hex: "00 06 05 00 02 00 20 01 01", replies: []),
        Case(name: "unknown group", hex: "AA 55 05 00 02 00 20 01 01", replies: []),
        Case(name: "unknown feature id", hex: "AA 06 05 00 02 00 7F 01 01", replies: []),
        Case(name: "unknown equalizer preset", hex: equalizerFrame(preset: "FF"), replies: []),
        Case(name: "smart audio with unknown payload", hex: "AA 80 09 02 01 02 03 04 05 06 07 08", replies: []),
        Case(name: "truncated equalizer", hex: "AA A2 74 00 04", replies: []),
        Case(name: "truncated battery", hex: "AA 06 05 00 02 00 1A 02 00", replies: []),
        Case(name: "truncated spatial audio", hex: "AA 06 06 00 02 00 0C 02 01", replies: []),
        Case(name: "truncated smart audio", hex: "AA 80 09 02 00 01 2E 00", replies: []),
        Case(name: "truncated balance", hex: "AA A8 05 02 01 01 02", replies: []),
        Case(name: "truncated volume limiter", hex: "AA 06 05 00 02 00 20 01", replies: []),
        Case(name: "truncated call voice", hex: "AA 06 07 00 02 00 16 03 FF FF", replies: []),
        Case(name: "truncated mode", hex: "AA 91 09 12 01 01", replies: []),
        Case(name: "truncated levels", hex: "AA 91 05 22", replies: []),
    ]

    /// A full-length equalizer reply: `AA A2 74 00 04 <preset>` padded to the 120 bytes its length byte promises.
    static func equalizerFrame(preset: String) -> String {
        "AA A2 74 00 04 \(preset)" + String(repeating: " 00", count: 114)
    }

    static let mode = "AA 91 09 12 01 01 02 00 03 00 04 07"
    static let spatial = "AA 06 06 00 02 00 0C 02 01 01"
    static let battery = "AA 06 0A 00 02 00 1A 02 00 50 1B 02 00 4B"

    /// Several frames in one notification are all decoded, in order.
    static let concatenated: [Case] = [
        Case(name: "mode + spatial", hex: "\(mode) \(spatial)",
             replies: [.noiseCancelingLevel(7), .listeningMode(.noiseCanceling), .spatialAudio(.off)]),
        Case(name: "spatial + mode", hex: "\(spatial) \(mode)",
             replies: [.spatialAudio(.off), .noiseCancelingLevel(7), .listeningMode(.noiseCanceling)]),
        Case(name: "battery + spatial", hex: "\(battery) \(spatial)",
             replies: [.battery(.left, percent: 80), .battery(.right, percent: 75), .spatialAudio(.off)]),
        Case(name: "valid frame then a cut-off one", hex: "\(spatial) AA 06 06 00 02",
             replies: [.spatialAudio(.off)]),
        Case(name: "valid frame then trailing garbage", hex: "\(spatial) 00 11 22",
             replies: [.spatialAudio(.off)]),
    ]

    /// A frame whose length byte disagrees with its contents is rejected.
    static let badLength: [Case] = [
        Case(name: "length too long", hex: "AA 06 40 00 02 00 0C 02 01 01", replies: []),
        Case(name: "length too short", hex: "AA 06 05 00 02 00 0C 02 01 01", replies: []),
        Case(name: "length zero", hex: "AA 06 00 00 02 00 0C 02 01 01", replies: []),
        Case(name: "bad frame hides the next one", hex: "AA 06 40 00 02 00 0C 02 01 01 \(spatial)", replies: []),
    ]

    @Test(arguments: concatenated)
    func decodesEveryFrame(_ testCase: Case) {
        #expect(JBLReply.decode(bytes(testCase.hex)) == testCase.replies)
    }

    @Test(arguments: badLength)
    func rejectsWrongLength(_ testCase: Case) {
        #expect(JBLReply.decode(bytes(testCase.hex)) == testCase.replies)
    }

    @Test(arguments: decoded)
    func decodes(_ testCase: Case) {
        #expect(JBLReply.decode(bytes(testCase.hex)) == testCase.replies)
    }

    @Test(arguments: ignored)
    func ignoresMalformedPackets(_ testCase: Case) {
        #expect(JBLReply.decode(bytes(testCase.hex)).isEmpty)
    }

    /// No prefix of any valid packet may crash the decoder.
    @Test(arguments: decoded + concatenated)
    func survivesEveryTruncation(_ testCase: Case) {
        let packet = bytes(testCase.hex)
        for length in 0...packet.count {
            _ = JBLReply.decode(Array(packet.prefix(length)))
        }
    }
}

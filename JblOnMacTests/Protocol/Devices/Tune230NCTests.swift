@testable import JblOnMac
import Testing

/// The Tune 230NC dialect. Every expected packet is copied from the PacketLogger capture of the
/// JBL app talking to a Tune 230NC TWS.
struct Tune230NCTests {
    /// The captured write of the Club preset, chunk by chunk.
    static let clubUpload = [
        "AA 41 B3 03",
        "00 04 00 C8 0D 2C 41 30 00 00 00 00 00 00 00 00 0A 00 00 00 01 00 00 00 00 00 80 40 " +
            "00 00 00 42 00 00 80 3F 01 00 00 00 00 00 00 40 00 00 80 42 00 00 80 3F 01 00 00 00 " +
            "00 00 80 3F 00 00 FA 42 00 00 80 3F 01 00 00 00 00 00 20 40 00 00 7A 43",
        "01 00 00 80 3F 01 00 00 00 00 00 C0 BF 00 00 FA 43 00 00 80 3F 01 00 00 00 00 00 C0 " +
            "BF 00 00 7A 44 00 00 80 3F 01 00 00 00 00 00 00 00 00 00 FA 44 00 00 80 3F 01 00 00 " +
            "00 00 00 80 3F 00 00 7A 45 00 00 80 3F 01 00 00 00 00 00 00 40 00 00 FA",
        "02 45 00 00 80 3F 01 00 00 00 00 00 80 40 00 00 7A 46 00 00 80 3F",
        "AA 05 41"
    ]

    /// The chunks of the captured equalizer download while Club was active, without `AA 43` and `AA 04 43`.
    static let clubDownload = [
        "00 04 01 00 00 00 00 00 00 00 00 00 0A 00 00 00 01 00 00 00 00 00 80 40 00 00 00 42 " +
            "00 00 80 3F 01 00 00 00 00 00 00 40 00 00 80 42 00 00 80 3F 01 00 00 00 00 00 80 3F " +
            "00 00 FA 42 00 00 80 3F 01 00 00 00 00 00 20 40 00 00 7A 43 00 00 80 3F",
        "01 01 00 00 00 00 00 C0 BF 00 00 FA 43 00 00 80 3F 01 00 00 00 00 00 C0 BF 00 00 7A " +
            "44 00 00 80 3F 01 00 00 00 00 00 00 00 00 00 FA 44 00 00 80 3F 01 00 00 00 00 00 80 " +
            "3F 00 00 7A 45 00 00 80 3F 01 00 00 00 00 00 00 40 00 00 FA 45 00 00 80",
        "02 3F 01 00 00 00 00 00 80 40 00 00 7A 46 00 00 80 3F"
    ]

    @Test func queries() {
        #expect(JBLCommand.queryBatteryLevels.bytes == bytes("AA 25 01 00"))
        #expect(JBLCommand.queryEqualizerCurve.bytes == bytes("AA 42 01 01"))
        #expect(JBLCommand.acknowledgeDownload.bytes == bytes("AA 01 02 43 00"))
        #expect(JBLCommand.queryTune230NCSmartAudio.bytes == bytes("AA 82 00"))
        #expect(JBLCommand.queryTune230NCVoiceAware.bytes == bytes("AA 98 01 01"))
        #expect(JBLCommand.queryStatus.bytes == bytes("AA 11 00"))
        #expect(JBLCommand.queryCaseFirmware.bytes == bytes("AA 26 01 00"))
        #expect(JBLModel.tune230NC.initialQueries.last == .queryEqualizerCurve)
    }

    @Test func smartAudioAndVoiceAwareWrites() {
        #expect(JBLCommand.setTune230NCSmartAudio(.off).bytes == bytes("AA 81 08 C5 00 2E 00 18 01 FF FF"))
        #expect(JBLCommand.setTune230NCSmartAudio(.audio).bytes == bytes("AA 81 08 00 01 2E 00 18 01 FF FF"))
        #expect(JBLCommand.setTune230NCSmartAudio(.video).bytes == bytes("AA 81 08 C5 00 2E 00 78 00 FF FF"))
        #expect(JBLCommand.setTune230NCVoiceAware(nil).bytes == bytes("AA 98 02 00 00"))
        #expect(JBLCommand.setTune230NCVoiceAware(.low).bytes == bytes("AA 98 02 00 01"))
        #expect(JBLCommand.setTune230NCVoiceAware(.high).bytes == bytes("AA 98 02 00 03"))
        #expect(JBLCommand.setTune230NCSmartAudio(.video).refreshQuery == .queryTune230NCSmartAudio)
        #expect(JBLCommand.setTune230NCVoiceAware(.mid).refreshQuery == .queryTune230NCVoiceAware)
    }

    @Test(arguments: [
        (
            EarbudSide.left,
            GestureControl.volume,
            GestureControl.ambientSound,
            "AA 77 0B 00 06 08 07 05 08 06 0C A1 0E A1"
        ),
        (.left, .ambientSound, .volume, "AA 77 0B 00 06 09 07 04 08 00 0C A1 0E A1"),
        (.left, .playback, .volume, "AA 77 0B 00 06 01 07 02 08 00 0C A1 0E A1"),
        (.left, .none, .volume, "AA 77 0B 00 06 00 07 00 08 00 0C 00 0E A1"),
        (.right, .ambientSound, .volume, "AA 77 0B 00 09 09 0A 04 0B 00 0E A1 0C A1"),
        (.right, .playback, .volume, "AA 77 0B 00 09 01 0A 02 0B 00 0E A1 0C A1"),
        (.right, .none, .volume, "AA 77 0B 00 09 00 0A 00 0B 00 0E 00 0C A1"),
        (.right, .volume, .volume, "AA 77 0B 00 09 08 0A 05 0B 06 0E A1 0C A1")
    ])
    func gestureWrites(side: EarbudSide, control: GestureControl, other: GestureControl, hex: String) {
        let command = JBLModel.tune230NC.gestureCommand(side, control, other: other)
        #expect(command.bytes == bytes(hex))
        #expect(command.refreshQuery == .queryGestureControls)
    }

    @Test func equalizerUploadMatchesTheCapture() {
        let packets = JBLCommand.equalizerUpload(.club)
        #expect(packets.map(\.bytes) == Self.clubUpload.map(bytes))
        #expect(packets.allSatisfy { $0.refreshQuery == .queryEqualizerCurve })
    }

    /// Off, Vocal, Bass, Jazz and Studio were captured too; check their gains and headroom bytes.
    @Test(arguments: [
        (EqualizerPreset.off, "04 00 00 00 00 00 30", [Float](repeating: 0, count: 10)),
        (.vocal, "04 00 00 00 00 00 30", [-1.5, -3, -3, 1, 3.5, 3.5, 3, 1.5, 0, -1.5]),
        (.bass, "04 00 E1 48 4F 41 30", [6, 3, 3, 2.5, 0.5, 0, 0, 0, 0, 0]),
        (.jazz, "04 00 00 00 00 00 30", [1, 0, 1, 0, 0, 0, -2, 2, 0, 3]),
        (.studio, "04 00 00 00 00 00 30", [0, -2, -2, 0, 0, 0, 0, 0, 0, 0])
    ])
    func equalizerUploadPayload(preset: EqualizerPreset, header: String, gains: [Float]) {
        let packets = JBLCommand.equalizerUpload(preset)
        let payload = packets.compactMap { packet -> [UInt8]? in
            guard case .uploadChunk = packet else { return nil }
            return Array(packet.bytes.dropFirst())
        }.flatMap(\.self)
        #expect(payload.count == 179)
        #expect(Array(payload.prefix(7)) == bytes(header))
        #expect(preset.tune230NCGains == gains)
    }

    @Test func decodesTheEqualizerDownload() {
        let payload = Self.clubDownload.map { Array(bytes($0).dropFirst()) }.flatMap(\.self)
        #expect(payload.count == 0xAF)
        #expect(JBLReply.equalizerGains(fromDownload: payload) == EqualizerPreset.club.tune230NCGains)
    }

    /// The factory curve read with `AA 42 01 00` has eight bands, so it isn't taken for a preset.
    @Test func ignoresTheEightBandCurve() {
        let payload = bytes("04 00 00 00 00 18 C1 00 00 18 C1 08 00 00 00") + [UInt8](repeating: 0, count: 128)
        #expect(JBLReply.equalizerGains(fromDownload: payload) == nil)
    }

    nonisolated static let replies: [(String, [JBLReply])] = [
        // Captured while the JBL app showed left 60%, right 50% and the case at 2%.
        ("AA 25 0D 01 00 00 3C 32 00 02 5B 0F 0A 0F 54 00",
         [.battery(.left, percent: 60), .battery(.right, percent: 50), .battery(.chargingCase, percent: 2)]),
        ("AA 25 0D 01 00 00 46 3C 00 50 74 0F 50 0F 54 00",
         [.battery(.left, percent: 70), .battery(.right, percent: 60), .battery(.chargingCase, percent: 80)]),
        ("AA 83 08 C5 00 2E 00 78 00 FF FF", [.smartAudio(.video)]),
        ("AA 83 08 00 01 2E 00 18 01 FF FF", [.smartAudio(.audio)]),
        ("AA 98 02 02 00", [.voiceAware(enabled: false, level: nil)]),
        ("AA 98 02 02 02", [.voiceAware(enabled: true, level: .mid)]),
        ("AA 98 02 00 02", []),
        (
            "AA 12 25 4A 42 4C 20 54 55 4E 45 32 33 30 4E 43 20 54 00 4B 20 00 32 90 7E E2 32 " +
                "59 68 03 07 00 3C 32 5B 0F 04 00 01 00",
            [.firmware("3.7.0")]
        ),
        ("AA 26 04 01 01 02 06", [.caseFirmware("1.2.6")]),
        ("AA 00 02 41 00", [.acknowledged(group: 0x41, status: 0)]),
        ("AA 43 AF 03", [.downloadStarted(length: 0xAF, chunks: 3)]),
        ("AA 04 43", [.downloadFinished]),
        ("AA 91 07 12 01 00 02 01 03 00", [.listeningMode(.ambientAware)]),
        // A write echo carries the written side fully and only the other side's last slot.
        ("AA 77 0B 02 09 09 0A 04 0B 00 0E A1 0C A1", [.gestureControl(.right, .ambientSound)]),
        ("AA 77 11 02 06 08 07 05 08 06 0C A1 09 09 0A 04 0B 00 0E A1",
         [.gestureControl(.left, .volume), .gestureControl(.right, .ambientSound)])
    ]

    @Test(arguments: replies)
    func decodesReplies(hex: String, replies: [JBLReply]) {
        #expect(JBLReply.decode(bytes(hex)) == replies)
    }
}

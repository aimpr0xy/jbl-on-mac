@testable import JblOnMac
import Testing

/// How `JBLReply.decode` splits a notification into frames, whatever the dialect. Most frames here
/// are Tune Beam 2 ones; only their framing matters.
struct JBLReplyTests {
    nonisolated static let mode = "AA 91 09 12 01 01 02 00 03 00 04 07"
    nonisolated static let spatial = "AA 06 06 00 02 00 0C 02 01 01"
    nonisolated static let battery = "AA 06 0A 00 02 00 1A 02 00 50 1B 02 00 4B"

    /// Several frames in one notification are all decoded, in order.
    nonisolated static let concatenated: [ReplyCase] = [
        ReplyCase(name: "mode + spatial", hex: "\(mode) \(spatial)",
                  replies: [.noiseCancelingLevel(7), .listeningMode(.noiseCanceling), .spatialAudio(.off)]),
        ReplyCase(name: "spatial + mode", hex: "\(spatial) \(mode)",
                  replies: [.spatialAudio(.off), .noiseCancelingLevel(7), .listeningMode(.noiseCanceling)]),
        ReplyCase(name: "battery + spatial", hex: "\(battery) \(spatial)",
                  replies: [.battery(.left, percent: 80), .battery(.right, percent: 75), .spatialAudio(.off)]),
        ReplyCase(name: "valid frame then a cut-off one", hex: "\(spatial) AA 06 06 00 02",
                  replies: [.spatialAudio(.off)]),
        ReplyCase(name: "valid frame then trailing garbage", hex: "\(spatial) 00 11 22",
                  replies: [.spatialAudio(.off)])
    ]

    /// A frame whose length byte disagrees with its contents is rejected.
    nonisolated static let badLength: [ReplyCase] = [
        ReplyCase(name: "length too long", hex: "AA 06 40 00 02 00 0C 02 01 01", replies: []),
        ReplyCase(name: "length too short", hex: "AA 06 05 00 02 00 0C 02 01 01", replies: []),
        ReplyCase(name: "length zero", hex: "AA 06 00 00 02 00 0C 02 01 01", replies: []),
        ReplyCase(name: "bad frame hides the next one", hex: "AA 06 40 00 02 00 0C 02 01 01 \(spatial)", replies: [])
    ]

    /// Frames without a length byte (Tune 230NC downloads) don't stop the frames after them
    /// from being decoded.
    nonisolated static let unlengthed: [ReplyCase] = [
        ReplyCase(name: "download end + ack", hex: "AA 04 43 AA 00 02 41 00",
                  replies: [.downloadFinished, .acknowledged(group: 0x41, status: 0)])
    ]

    /// Packets that must decode to nothing in any dialect: empty, cut short, or not a frame.
    nonisolated static let ignored: [ReplyCase] = [
        ReplyCase(name: "empty", hex: "", replies: []),
        ReplyCase(name: "header only", hex: "AA", replies: []),
        ReplyCase(name: "wrong start byte", hex: "00 06 05 00 02 00 20 01 01", replies: []),
        ReplyCase(name: "unknown group", hex: "AA 55 05 00 02 00 20 01 01", replies: [])
    ]

    @Test(arguments: concatenated + unlengthed)
    func decodesEveryFrame(_ testCase: ReplyCase) {
        #expect(JBLReply.decode(bytes(testCase.hex)) == testCase.replies)
    }

    @Test(arguments: badLength)
    func rejectsWrongLength(_ testCase: ReplyCase) {
        #expect(JBLReply.decode(bytes(testCase.hex)) == testCase.replies)
    }

    @Test(arguments: ignored)
    func ignoresMalformedPackets(_ testCase: ReplyCase) {
        #expect(JBLReply.decode(bytes(testCase.hex)).isEmpty)
    }

    /// No prefix of any valid notification may crash the decoder.
    @Test(arguments: concatenated + unlengthed)
    func survivesEveryTruncation(_ testCase: ReplyCase) {
        let packet = bytes(testCase.hex)
        for length in 0 ... packet.count {
            _ = JBLReply.decode(Array(packet.prefix(length)))
        }
    }
}

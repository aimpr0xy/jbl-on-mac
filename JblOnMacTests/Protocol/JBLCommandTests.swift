@testable import JblOnMac
import Testing

struct JBLCommandTests {
    @Test(arguments: [
        (JBLCommand.setListeningMode(.noiseCanceling), JBLCommand.queryListeningMode),
        (.setLevel(.noiseCanceling, 3), .queryLevels),
        (.setSpatialAudio(.off), .querySpatialAudio),
        (.setSmartAudio(.off), .querySmartAudio),
        (.setBalance(2), .queryBalance),
        (.setVolumeLimiter(true), .queryVolumeLimiter),
        (.setSoundLevelOptimizer(true), .queryCallFeature(id: 0x23)),
        (.setEqualizer(.club), .queryEqualizer),
        (.setTune230NCSmartAudio(.off), .queryTune230NCSmartAudio),
        (.setTune230NCVoiceAware(nil), .queryTune230NCVoiceAware),
        (.finishUpload, .queryEqualizerCurve)
    ])
    func aWriteIsRefreshedByTheQueryForThatState(write: JBLCommand, query: JBLCommand) {
        #expect(write.refreshQuery == query)
    }

    @Test(arguments: [
        JBLCommand.queryListeningMode, .queryLevels, .queryBalance, .queryBatteryLevels, .queryStatus,
        .queryCallFeature(id: 0x0D), .acknowledgeDownload
    ])
    func queriesAndAcknowledgementsNeedNoRefresh(command: JBLCommand) {
        #expect(command.refreshQuery == nil)
    }

    @Test func featureQueriesCarryTheFeatureId() {
        #expect(JBLCommand.queryCallFeature(id: 0x23).bytes == bytes("AA 06 03 00 01 00 23"))
        #expect(JBLCommand.queryCallFeature(id: 0x0D).bytes == bytes("AA 06 03 00 01 00 0D"))
    }

    @Test(arguments: EqualizerPreset.allCases)
    func anUploadIsAStartChunksInOrderAndAFinish(preset: EqualizerPreset) throws {
        let packets = JBLCommand.equalizerUpload(preset)
        guard case let .startUpload(length, chunks) = try #require(packets.first) else {
            Issue.record("an upload must start with .startUpload")
            return
        }
        #expect(packets.last == .finishUpload)
        let chunkPackets = packets.dropFirst().dropLast()
        #expect(chunkPackets.count == chunks)

        var total = 0
        for (index, packet) in chunkPackets.enumerated() {
            guard case let .uploadChunk(chunkIndex, payload) = packet else {
                Issue.record("only chunks may sit between the start and the finish")
                return
            }
            #expect(chunkIndex == index)
            total += payload.count
        }
        #expect(total == length)
    }
}

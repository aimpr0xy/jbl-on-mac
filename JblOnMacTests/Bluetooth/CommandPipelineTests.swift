import Foundation
@testable import JblOnMac
import Testing

@MainActor
struct CommandPipelineTests {
    private static let ack = bytes("AA 00 02 41 00")
    private static let rejected = bytes("AA 00 02 41 01")
    private static let timer = CommandPipeline.Action.startTimer(CommandPipeline.transferTimeout)

    private var clubChunks: [[UInt8]] {
        Tune230NCTests.clubDownload.map { bytes($0) }
    }

    private func writes(_ actions: [CommandPipeline.Action]) -> [JBLCommand] {
        actions.compactMap { action in
            if case let .write(command) = action {
                command
            } else {
                nil
            }
        }
    }

    /// A pipeline in the middle of a Club upload with its first packet written.
    private func uploading(_ preset: EqualizerPreset = .club) -> CommandPipeline {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.uploadEqualizer(preset))
        return pipeline
    }

    // MARK: - Writes

    @Test func aSentCommandIsWrittenAndRemembered() {
        var pipeline = CommandPipeline()
        let actions = pipeline.handle(.send(.setBalance(2)))
        #expect(actions == [.write(.setBalance(2))])
        #expect(pipeline.pendingWrites == [.setBalance(2)])
    }

    @Test func writeResultsArriveInOrder() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.send(.setBalance(2)))
        _ = pipeline.handle(.send(.setVolumeLimiter(true)))
        _ = pipeline.handle(.send(.setSpatialAudio(.off)))
        #expect(pipeline.handle(.writeCompleted(error: nil)).isEmpty)
        #expect(pipeline.pendingWrites == [.setVolumeLimiter(true), .setSpatialAudio(.off)])
        // The second write failed: only its own refresh query goes out.
        let actions = pipeline.handle(.writeCompleted(error: "boom"))
        #expect(writes(actions) == [.queryVolumeLimiter])
        #expect(pipeline.pendingWrites == [.setSpatialAudio(.off), .queryVolumeLimiter])
    }

    @Test func aFailedWriteSendsItsRefreshQueryAndLogsAnError() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.send(.setBalance(2)))
        let actions = pipeline.handle(.writeCompleted(error: "boom"))
        #expect(writes(actions) == [.queryBalance])
        #expect(actions.first == .log("write failed for setBalance(2): boom", isError: true))
    }

    @Test func aSuccessfulWriteSendsNothing() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.send(.setBalance(2)))
        #expect(pipeline.handle(.writeCompleted(error: nil)).isEmpty)
        #expect(pipeline.pendingWrites.isEmpty)
    }

    @Test func aFailedQueryHasNothingToRefresh() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.send(.queryBalance))
        let actions = pipeline.handle(.writeCompleted(error: "boom"))
        #expect(writes(actions).isEmpty)
    }

    @Test func aWriteResultWithNothingPendingIsIgnored() {
        var pipeline = CommandPipeline()
        #expect(pipeline.handle(.writeCompleted(error: "boom")).isEmpty)
        #expect(pipeline == CommandPipeline())
    }

    // MARK: - Upload

    @Test func anUploadSendsOnePacketPerAcknowledgement() {
        let packets = JBLCommand.equalizerUpload(.club)
        var pipeline = CommandPipeline()
        #expect(pipeline.handle(.uploadEqualizer(.club)) == [.write(packets[0]), Self.timer])
        for packet in packets.dropFirst() {
            #expect(pipeline.handle(.notified(Self.ack)) == [.write(packet), Self.timer])
        }
        #expect(pipeline.uploadRemaining == [])
        // The ack of the last packet ends the upload and its timeout.
        #expect(pipeline.handle(.notified(Self.ack)) == [.cancelTimer])
        #expect(pipeline.uploadRemaining == nil)
    }

    @Test func aPresetPickedDuringAnUploadIsSentAfterwards() {
        let club = JBLCommand.equalizerUpload(.club)
        let vocal = JBLCommand.equalizerUpload(.vocal)
        var pipeline = uploading(.club)
        #expect(pipeline.handle(.uploadEqualizer(.vocal)).isEmpty)
        #expect(pipeline.queuedEqualizer == .vocal)
        for _ in club.dropFirst() {
            _ = pipeline.handle(.notified(Self.ack))
        }
        #expect(pipeline.handle(.notified(Self.ack)) == [.write(vocal[0]), Self.timer])
        #expect(pipeline.queuedEqualizer == nil)
        #expect(pipeline.uploadRemaining == Array(vocal.dropFirst()))
    }

    @Test func aRejectedAcknowledgementStopsTheUploadAndRequeriesTheCurve() {
        var pipeline = uploading()
        _ = pipeline.handle(.uploadEqualizer(.vocal))
        let actions = pipeline.handle(.notified(Self.rejected))
        #expect(actions == [
            .log("equalizer upload rejected with status 1", isError: true),
            .write(.queryEqualizerCurve),
            .cancelTimer
        ])
        #expect(pipeline.uploadRemaining == nil)
        #expect(pipeline.queuedEqualizer == nil)
    }

    @Test func aFailedUploadPacketDropsTheRestOfTheUpload() {
        var pipeline = uploading()
        _ = pipeline.handle(.uploadEqualizer(.vocal))
        let actions = pipeline.handle(.writeCompleted(error: "boom"))
        #expect(writes(actions) == [.queryEqualizerCurve])
        #expect(actions.contains(.cancelTimer))
        #expect(pipeline.uploadRemaining == nil)
        #expect(pipeline.queuedEqualizer == nil)
    }

    @Test func aFailedOrdinaryWriteKeepsTheUpload() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.send(.setBalance(2)))
        _ = pipeline.handle(.uploadEqualizer(.club))
        _ = pipeline.handle(.writeCompleted(error: "boom"))
        #expect(pipeline.uploadRemaining == Array(JBLCommand.equalizerUpload(.club).dropFirst()))
    }

    @Test func acknowledgementsWithoutAnUploadAreIgnored() {
        var pipeline = CommandPipeline()
        #expect(pipeline.handle(.notified(Self.ack)).isEmpty)
        // Other groups are ordinary replies.
        #expect(pipeline.handle(.notified(bytes("AA 00 02 99 01"))) == [.apply(.acknowledged(group: 0x99, status: 1))])
    }

    // MARK: - Download

    @Test func downloadedChunksAreBufferedAndAcknowledged() {
        var pipeline = CommandPipeline()
        let started = pipeline.handle(.notified(bytes("AA 43 AF 03")))
        #expect(started == [.write(.acknowledgeDownload), Self.timer])
        #expect(pipeline.downloadBuffer == [])
        for chunk in clubChunks {
            #expect(pipeline.handle(.notified(chunk)) == [.write(.acknowledgeDownload), Self.timer])
        }
        #expect(pipeline.downloadBuffer == clubChunks.flatMap { Array($0.dropFirst()) })
    }

    @Test func aFinishedDownloadOfAPresetCurveSelectsThatPreset() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.notified(bytes("AA 43 AF 03")))
        for chunk in clubChunks {
            _ = pipeline.handle(.notified(chunk))
        }
        let actions = pipeline.handle(.notified(bytes("AA 04 43")), presets: EqualizerPreset.allCases)
        #expect(actions == [.equalizerDownloaded(.club), .write(.acknowledgeDownload), .cancelTimer])
        #expect(pipeline.downloadBuffer == nil)
    }

    @Test func aFinishedDownloadOfACustomCurveMapsToNoPreset() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.notified(bytes("AA 43 AF 03")))
        _ = pipeline.handle(.notified(bytes("00 01 02")))
        let actions = pipeline.handle(.notified(bytes("AA 04 43")), presets: EqualizerPreset.allCases)
        #expect(actions.first == .equalizerDownloaded(nil))
    }

    @Test func framesAreStillDecodedDuringADownload() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.notified(bytes("AA 43 AF 03")))
        #expect(pipeline
            .handle(.notified(bytes("AA 91 07 12 01 00 02 01 03 00"))) == [.apply(.listeningMode(.ambientAware))])
    }

    @Test func aNonFrameWithoutADownloadIsDecodedAsNothing() {
        var pipeline = CommandPipeline()
        #expect(pipeline.handle(.notified(bytes("00 01 02"))).isEmpty)
    }

    // MARK: - Timeout

    @Test func anUploadWhoseAcknowledgementNeverComesTimesOut() {
        var pipeline = uploading()
        let actions = pipeline.handle(.timerFired)
        #expect(actions == [
            .log("equalizer transfer timed out", isError: true),
            .write(.queryEqualizerCurve),
            .cancelTimer
        ])
        #expect(pipeline.uploadRemaining == nil)
        // The next preset is sent instead of being queued forever.
        #expect(writes(pipeline.handle(.uploadEqualizer(.vocal))) == [JBLCommand.equalizerUpload(.vocal)[0]])
    }

    @Test func aDownloadThatNeverFinishesTimesOutAndLaterFramesDecode() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.notified(bytes("AA 43 AF 03")))
        _ = pipeline.handle(.notified(clubChunks[0]))
        let actions = pipeline.handle(.timerFired)
        #expect(actions.first == .log("equalizer transfer timed out", isError: true))
        #expect(writes(actions) == [.queryEqualizerCurve])
        #expect(pipeline.downloadBuffer == nil)
        #expect(pipeline.handle(.notified(bytes("00 01 02"))).isEmpty)
        #expect(pipeline
            .handle(.notified(bytes("AA 91 07 12 01 00 02 01 03 00"))) == [.apply(.listeningMode(.ambientAware))])
    }

    @Test func aQueuedPresetIsRetriedOnceAfterATimeout() {
        let vocal = JBLCommand.equalizerUpload(.vocal)
        var pipeline = uploading()
        _ = pipeline.handle(.uploadEqualizer(.vocal))
        let actions = pipeline.handle(.timerFired)
        #expect(writes(actions) == [.queryEqualizerCurve, vocal[0]])
        #expect(actions.last == Self.timer)
        #expect(pipeline.uploadRemaining == Array(vocal.dropFirst()))
        #expect(pipeline.queuedEqualizer == nil)
    }

    @Test func aRetryThatTimesOutIsNotRetriedAgain() {
        var pipeline = uploading()
        _ = pipeline.handle(.uploadEqualizer(.vocal))
        _ = pipeline.handle(.timerFired)
        _ = pipeline.handle(.uploadEqualizer(.jazz))
        let actions = pipeline.handle(.timerFired)
        #expect(writes(actions) == [.queryEqualizerCurve])
        #expect(pipeline.uploadRemaining == nil)
        #expect(pipeline.queuedEqualizer == nil)
    }

    @Test func aRetryThatSucceedsAllowsALaterRetry() {
        var pipeline = uploading()
        _ = pipeline.handle(.uploadEqualizer(.vocal))
        _ = pipeline.handle(.timerFired)
        for _ in JBLCommand.equalizerUpload(.vocal) {
            _ = pipeline.handle(.notified(Self.ack))
        }
        _ = pipeline.handle(.uploadEqualizer(.jazz))
        _ = pipeline.handle(.uploadEqualizer(.bass))
        let actions = pipeline.handle(.timerFired)
        #expect(writes(actions) == [.queryEqualizerCurve, JBLCommand.equalizerUpload(.bass)[0]])
    }

    @Test func aTimerFiringWithoutATransferDoesNothing() {
        var pipeline = CommandPipeline()
        #expect(pipeline.handle(.timerFired).isEmpty)
    }

    // MARK: - Link

    @Test func aDroppedLinkClearsEverything() {
        var pipeline = uploading()
        _ = pipeline.handle(.uploadEqualizer(.vocal))
        _ = pipeline.handle(.send(.setBalance(1)))
        _ = pipeline.handle(.notified(bytes("AA 43 AF 03")))
        #expect(pipeline.handle(.linkDropped) == [.cancelTimer])
        #expect(pipeline == CommandPipeline())
    }

    @Test func aDroppedLinkWithoutATransferHasNoTimerToCancel() {
        var pipeline = CommandPipeline()
        _ = pipeline.handle(.send(.setBalance(1)))
        #expect(pipeline.handle(.linkDropped).isEmpty)
        #expect(pipeline.pendingWrites.isEmpty)
    }

    @Test func otherRepliesArePassedOn() {
        var pipeline = CommandPipeline()
        #expect(pipeline
            .handle(.notified(bytes("AA 91 07 12 01 00 02 01 03 00"))) == [.apply(.listeningMode(.ambientAware))])
    }
}

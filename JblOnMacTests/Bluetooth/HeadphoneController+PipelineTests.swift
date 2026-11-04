import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct PipelineTests {
        private var clubDownload: [[UInt8]] {
            Tune230NCTests.clubDownload.map { bytes($0) }
        }

        @Test func aFinishedDownloadOfAPresetCurveSelectsThatPreset() {
            ControllerFixture.withController { controller in
                controller.run(.notified(bytes("AA 43 AF 03")))
                for chunk in clubDownload {
                    controller.run(.notified(chunk))
                }
                controller.run(.notified(bytes("AA 04 43")))
                #expect(controller.state.equalizer == .club)
                #expect(controller.pipeline.downloadBuffer == nil)
                #expect(controller.transferTimer == nil)
            }
        }

        @Test func aFinishedDownloadOfACustomCurveLeavesTheEqualizerAlone() {
            ControllerFixture.withController { controller in
                controller.state.equalizer = .bass
                controller.run(.notified(bytes("AA 43 AF 03")))
                controller.run(.notified(bytes("00 01 02")))
                controller.run(.notified(bytes("AA 04 43")))
                #expect(controller.state.equalizer == .bass)
            }
        }

        @Test func repliesAreCopiedIntoTheState() {
            ControllerFixture.withController { controller in
                controller.run(.notified(bytes("AA 91 07 12 01 00 02 01 03 00")))
                #expect(controller.state.mode == .ambientAware)
            }
        }

        @Test func aTransferStartsATimerThatEndsWithTheTransfer() {
            ControllerFixture.withController { controller in
                controller.run(.uploadEqualizer(.club))
                #expect(controller.transferTimer != nil)
                for _ in JBLCommand.equalizerUpload(.club) {
                    controller.run(.notified(bytes("AA 00 02 41 00")))
                }
                #expect(controller.pipeline.uploadRemaining == nil)
                #expect(controller.transferTimer == nil)
            }
        }

        @Test func aFiringTimerAbandonsTheStuckUpload() {
            ControllerFixture.withController { controller in
                controller.run(.uploadEqualizer(.club))
                controller.run(.timerFired)
                #expect(controller.pipeline.uploadRemaining == nil)
                #expect(controller.transferTimer == nil)
            }
        }

        @Test func theTimerFiresOnItsOwnAfterTheTimeout() async throws {
            var stuck: HeadphoneController?
            ControllerFixture.withController { controller in
                controller.run(.uploadEqualizer(.club))
                stuck = controller
            }
            try await Task.sleep(for: CommandPipeline.transferTimeout + .seconds(1))
            #expect(stuck?.pipeline.uploadRemaining == nil)
            #expect(stuck?.transferTimer == nil)
        }
    }
}

import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct HeadphoneControllerTests {
        @Test func aSuccessfulWriteIsRemovedFromThePendingOnes() {
            ControllerFixture.withController { controller in
                controller.pendingWrites = [.setBalance(2), .setBalance(3)]
                controller.writeCompleted(error: nil)
                #expect(controller.pendingWrites == [.setBalance(3)])
            }
        }

        @Test func aWriteResultWithNothingPendingIsIgnored() {
            ControllerFixture.withController { controller in
                controller.writeCompleted(error: CocoaError(.fileNoSuchFile))
                #expect(controller.pendingWrites.isEmpty)
            }
        }

        @Test func aFailedEqualizerUploadWriteDropsTheRestOfTheUpload() {
            ControllerFixture.withController { controller in
                controller.pendingWrites = [.finishUpload]
                controller.uploadRemaining = [.queryBalance]
                controller.queuedEqualizer = .club
                controller.writeCompleted(error: CocoaError(.fileWriteUnknown))
                #expect(controller.pendingWrites.isEmpty)
                #expect(controller.uploadRemaining == nil)
                #expect(controller.queuedEqualizer == nil)
            }
        }

        @Test func aFailedOrdinaryWriteKeepsTheUpload() {
            ControllerFixture.withController { controller in
                controller.pendingWrites = [.setBalance(2)]
                controller.uploadRemaining = [.queryBalance]
                controller.writeCompleted(error: CocoaError(.fileWriteUnknown))
                #expect(controller.uploadRemaining == [.queryBalance])
            }
        }
    }
}

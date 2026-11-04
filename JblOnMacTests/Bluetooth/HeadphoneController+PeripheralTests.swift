import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct PeripheralTests {
        private var clubDownload: [UInt8] {
            Tune230NCTests.clubDownload.flatMap { Array(bytes($0).dropFirst()) }
        }

        @Test func storedValueRepliesLandInTheState() {
            ControllerFixture.withController { controller in
                controller.apply(.balance(3))
                controller.apply(.listeningMode(.talkThru))
                #expect(controller.state.balance == 3)
                #expect(controller.state.mode == .talkThru)
            }
        }

        @Test func firmwareRepliesAreStoredAndSavedForNextTime() {
            ControllerFixture.withController { controller in
                controller.apply(.firmware("3.7.0"))
                controller.apply(.caseFirmware("1.0.0"))
                #expect(controller.state.info == DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0"))
                #expect(controller.savedDeviceInfo == DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0"))
            }
        }

        @Test func aFinishedDownloadOfAPresetCurveSelectsThatPreset() {
            ControllerFixture.withController { controller in
                controller.apply(.downloadStarted(length: 0xAF, chunks: 3))
                #expect(controller.downloadBuffer == [])
                controller.downloadBuffer?.append(contentsOf: clubDownload)
                controller.apply(.downloadFinished)
                #expect(controller.state.equalizer == .club)
                #expect(controller.downloadBuffer == nil)
            }
        }

        @Test func aFinishedDownloadOfAnUnknownCurveLeavesTheEqualizerAlone() {
            ControllerFixture.withController { controller in
                controller.state.equalizer = .bass
                controller.downloadBuffer = [0x01, 0x02]
                controller.apply(.downloadFinished)
                #expect(controller.state.equalizer == .bass)
                #expect(controller.downloadBuffer == nil)
            }
        }

        @Test func anAcknowledgedPacketSendsTheNextOne() {
            ControllerFixture.withController { controller in
                controller.uploadRemaining = [.queryEqualizerCurve, .queryBalance, .queryLevels]
                controller.apply(.acknowledged(group: 0x41, status: 0))
                #expect(controller.uploadRemaining == [.queryBalance, .queryLevels])
            }
        }

        @Test func aRejectedUploadPacketStopsTheUpload() {
            ControllerFixture.withController { controller in
                controller.uploadRemaining = [.queryBalance]
                controller.queuedEqualizer = .vocal
                controller.apply(.acknowledged(group: 0x41, status: 1))
                #expect(controller.uploadRemaining == nil)
                #expect(controller.queuedEqualizer == nil)
            }
        }
    }
}

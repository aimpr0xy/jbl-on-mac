@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
private func connected(name: String = "JBL Tune 230NC TWS") -> HeadphoneController {
    let controller = HeadphoneController()
    controller.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
    controller.status = .connected
    controller.state = DeviceState()
    return controller
}

@MainActor
private func controlsHeight(_ controller: HeadphoneController) -> CGFloat {
    let device = controller.selectedDevice ?? JBLDevice(name: "JBL", address: "AA:BB", isConnected: true)
    let view = DeviceControlsView(headphones: controller, device: device, screen: Box(Screen.controls).binding)
    return ViewHost.size(of: view).height
}

@MainActor
struct DeviceControlsViewTests {
    private func height(_ configure: (inout DeviceState) -> Void, name: String = "JBL Tune 230NC TWS") -> CGFloat {
        let controller = connected(name: name)
        configure(&controller.state)
        return controlsHeight(controller)
    }

    @Test func emptyStateStillShowsTheAlwaysPresentRows() {
        #expect(height { _ in } > 100)
    }

    @Test func smartAudioRowAppearsOnceReported() {
        let none = height { _ in }
        for mode in SmartAudioMode.allCases {
            #expect(height { $0.smartMode = mode } > none)
        }
        #expect(height { $0.smartMode = .off } == height { $0.smartMode = .audio })
    }

    @Test func spatialAudioRowAppearsOnceReported() {
        let none = height { _ in }
        for mode in SpatialAudioMode.allCases {
            #expect(height { $0.spatialMode = mode } > none)
        }
    }

    @Test func ambientSubtitleAppearsForEveryMode() {
        let none = height { _ in }
        for mode in ListeningMode.allCases {
            #expect(height { $0.mode = mode } > none)
        }
    }

    @Test func balanceRowAppearsForCenteredLeftAndRight() {
        let none = height { _ in }
        let centered = height { $0.balance = 0 }
        #expect(centered > none)
        #expect(height { $0.balance = -4 } == centered)
        #expect(height { $0.balance = 9 } == centered)
    }

    @Test func equalizerSubtitleAppearsOnceReported() {
        let none = height { _ in }
        for preset in EqualizerPreset.allCases {
            #expect(height { $0.equalizer = preset } > none)
        }
    }

    @Test func safeSoundRowAppearsOnceReported() {
        let none = height { _ in }
        #expect(height { $0.volumeLimiterEnabled = true } > none)
        #expect(height { $0.volumeLimiterEnabled = false } == height { $0.volumeLimiterEnabled = true })
    }

    @Test func touchControlRowsAppearPerEarbud() {
        let none = height { _ in }
        let left = height { $0.leftGestureControl = .volume }
        let right = height { $0.rightGestureControl = GestureControl.none }
        let both = height {
            $0.leftGestureControl = .playback
            $0.rightGestureControl = .ambientSound
        }
        #expect(left > none)
        #expect(right == left)
        #expect(both > left)
    }

    @Test func callsRowAppearsForAnyCallFeature() {
        let none = height { _ in }
        #expect(height { $0.soundLevelOptimizerEnabled = false } > none)
        #expect(height { $0.callSoundSetting = .natural } > none)
        #expect(height { $0.callVoiceSetting = .bright } > none)
        #expect(height { $0.voiceAwareEnabled = true } > none)
        let all = height {
            $0.soundLevelOptimizerEnabled = true
            $0.callSoundSetting = .natural
            $0.callVoiceSetting = .bright
            $0.voiceAwareEnabled = true
        }
        // One Calls row however many features are reported.
        #expect(all == height { $0.voiceAwareEnabled = true })
    }

    @Test func unsupportedModelShowsTheNote() {
        let supported = controlsHeight(connected())
        let unknown = controlsHeight(connected(name: "JBL Something Else"))
        #expect(unknown > supported)
        #expect(height({ _ in }, name: "JBL Tune Beam 2") == supported)
    }

    @Test func firmwareFooterAppearsWithAndWithoutCase() {
        let none = height { _ in }
        let earbuds = height { $0.info.firmware = "1.2.3" }
        let withCase = height {
            $0.info.firmware = "1.2.3"
            $0.info.caseFirmware = "4.5.6"
        }
        #expect(earbuds > none)
        #expect(withCase >= earbuds)
        // Case firmware alone is not shown.
        #expect(height { $0.info.caseFirmware = "4.5.6" } == none)
    }

    @Test func batteryRowAppearsForAnyReading() {
        let none = height { _ in }
        let left = height { $0.leftBattery = 80 }
        #expect(left > none)
        #expect(height { $0.rightBattery = 5 } == left)
        #expect(height { $0.caseBattery = 100 } == left)
        #expect(height {
            $0.leftBattery = 1
            $0.rightBattery = 2
            $0.caseBattery = 3
        } == left)
    }
}

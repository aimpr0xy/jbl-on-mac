@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct DeviceRowTests {
    private let connected = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:01", isConnected: true)

    private let paired = JBLDevice(name: "JBL Tune Beam 2", address: "AA:02", isConnected: false)

    private let unsupported = JBLDevice(name: "JBL Flip 6", address: "AA:03", isConnected: true)

    private func row(_ device: JBLDevice, _ configure: (HeadphoneController) -> Void = { _ in }) -> CGFloat {
        let controller = HeadphoneController()
        configure(controller)
        return ViewHost.size(of: DeviceRow(headphones: controller, device: device)).height
    }

    private func opening(_ status: HeadphoneController.Status) -> (HeadphoneController) -> Void {
        { controller in
            controller.selectedDevice = connected
            controller.status = status
        }
    }

    @Test func rowGetsASubtitleOnlyWhenTheSettingsLinkCannotBeMade() {
        let plain = row(connected)
        for status in [HeadphoneController.Status.idle, .scanning, .connecting, .connected] {
            #expect(row(connected, opening(status)) == plain)
        }
        for status in [HeadphoneController.Status.bluetoothOff, .unauthorized] {
            #expect(row(connected, opening(status)) > plain)
        }
        // Only the row being opened explains the problem.
        #expect(row(paired, opening(.bluetoothOff)) == row(paired))
    }

    @Test func rowRendersEveryConnectionState() {
        let idle = row(paired)
        #expect(row(connected) == idle)
        #expect(row(unsupported) == idle)
        #expect(row(paired) { $0.connectingAddress = "AA:02" } == idle)
        #expect(row(paired) { $0.connectingAddress = "AA:99" } == idle)
        #expect(row(connected) { $0.selectedDevice = connected } == idle)
        #expect(row(connected) { $0.selectedDevice = paired } == idle)
    }
}

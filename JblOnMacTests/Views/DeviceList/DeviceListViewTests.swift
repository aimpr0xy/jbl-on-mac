@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct DeviceListViewTests {
    private let connected = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:01", isConnected: true)

    private let paired = JBLDevice(name: "JBL Tune Beam 2", address: "AA:02", isConnected: false)

    private func list(_ configure: (HeadphoneController) -> Void) -> CGSize {
        let controller = HeadphoneController()
        controller.devices = []
        configure(controller)
        return ViewHost.size(of: DeviceListView(headphones: controller))
    }

    @Test func listGrowsWithEachDevice() {
        let empty = list { _ in }
        let one = list { $0.devices = [connected] }
        let two = list { $0.devices = [connected, paired] }
        #expect(empty.height > 0)
        #expect(two.height > one.height)
    }

    @Test func bluetoothOffReplacesTheListWithAMessage() {
        let off = list {
            $0.devices = [connected, paired]
            $0.isBluetoothOff = true
        }
        let offEmpty = list { $0.isBluetoothOff = true }
        let withList = list { $0.devices = [connected, paired] }
        #expect(off == offEmpty)
        #expect(off.height != withList.height)
    }
}

@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct GesturesScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    @Test func gesturesListsEveryOptionForBothSides() {
        let headphones = controller()
        headphones.state.leftGestureControl = .volume
        headphones.state.rightGestureControl = nil
        let box = Box(Screen.gestures(.left))
        let left = ViewHost.size(of: GesturesScreen(headphones: headphones, side: .left, screen: box.binding))
        let right = ViewHost.size(of: GesturesScreen(headphones: headphones, side: .right, screen: box.binding))
        #expect(left.height > 0)
        #expect(left == right)
    }
}

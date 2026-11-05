@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct BalanceScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    @Test func balanceScreenRendersCenterLeftAndRight() {
        let box = Box(Screen.balance)
        var heights: [CGFloat] = []
        for balance in [nil, 0, -16, 5] as [Int?] {
            let headphones = controller()
            headphones.state.balance = balance
            heights.append(ViewHost.size(of: BalanceScreen(headphones: headphones, screen: box.binding)).height)
        }
        #expect(heights[0] > 0)
        #expect(Set(heights).count == 1)
    }

    @Test func stepRoundsToTheNearestBalanceValue() {
        #expect(BalanceScreen.step(for: -3.6) == -4)
        #expect(BalanceScreen.step(for: -3.4) == -3)
        #expect(BalanceScreen.step(for: 4.5) == 5)
        #expect(BalanceScreen.step(for: 0.2) == 0)
        #expect(BalanceScreen.step(for: -16) == -16)
    }
}

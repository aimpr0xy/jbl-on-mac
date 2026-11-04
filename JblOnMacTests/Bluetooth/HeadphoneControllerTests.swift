import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct HeadphoneControllerTests {
        @Test func sendingDoesNothingWithoutALink() {
            ControllerFixture.withController { controller in
                controller.send(.setBalance(2))
                #expect(controller.pipeline == CommandPipeline())
            }
        }
    }
}

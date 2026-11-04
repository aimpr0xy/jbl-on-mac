@testable import JblOnMac
import Testing

struct ScreenTests {
    @Test func screensWithPayloadsAreToldApartByTheirPayload() {
        #expect(Screen.level(.noiseCanceling) != Screen.level(.ambientAware))
        #expect(Screen.gestures(.left) != Screen.gestures(.right))
        #expect(Screen.level(.noiseCanceling) == Screen.level(.noiseCanceling))
    }

    @Test func screensWorkAsSetMembers() {
        let screens: Set<Screen> = [.controls, .balance, .level(.ambientAware), .level(.ambientAware)]
        #expect(screens.count == 3)
        #expect(screens.contains(.level(.ambientAware)))
        #expect(!screens.contains(.equalizer))
    }
}

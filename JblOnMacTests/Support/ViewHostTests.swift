@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct ViewHostTests {
    @Test func reportsTheSizeOfAFixedSizeView() {
        let size = ViewHost.size(of: Color.clear.frame(width: 50, height: 30))
        #expect(size.width == 50)
        #expect(size.height == 30)
    }

    @Test func taller() {
        let one = ViewHost.size(of: VStack { Text("a") })
        let two = ViewHost.size(of: VStack { Text("a")
            Text("b")
        })
        #expect(two.height > one.height)
    }

    @Test func boxBindingWritesThroughToTheBox() {
        let box = Box(Screen.controls)
        box.binding.wrappedValue = .balance
        #expect(box.value == .balance)
    }
}

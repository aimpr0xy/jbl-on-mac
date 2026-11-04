@testable import JblOnMac
import Testing

struct LogFormattingTests {
    private enum LinkError: Error {
        case timedOut
    }

    @Test func describesNoErrorAsNil() {
        #expect(describe(nil) == "nil")
    }

    @Test func describesAnErrorByItsValue() {
        #expect(describe(LinkError.timedOut) == "timedOut")
    }
}

@testable import JblOnMac
import Testing

@MainActor
struct TaskAfterDelayTests {
    @Test func runsTheActionOnceTheDelayHasPassed() async {
        var fired = 0
        let task = Task.afterDelay(.milliseconds(10)) { fired += 1 }
        await task.value
        #expect(fired == 1)
    }

    @Test func doesNotRunTheActionBeforeTheDelay() {
        var fired = false
        let task = Task.afterDelay(.seconds(60)) { fired = true }
        #expect(!fired)
        task.cancel()
    }

    @Test func doesNotRunTheActionWhenCancelled() async {
        var fired = false
        let task = Task.afterDelay(.milliseconds(50)) { fired = true }
        task.cancel()
        await task.value
        #expect(!fired)
    }
}

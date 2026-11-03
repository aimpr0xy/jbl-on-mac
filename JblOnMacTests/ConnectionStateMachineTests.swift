import Foundation
import Testing
@testable import JblOnMac

struct ConnectionStateMachineTests {
    typealias Action = ConnectionStateMachine.Action

    let a = UUID()
    let b = UUID()

    /// A machine for a selected device that is connecting to `id` through its remembered identifier.
    func connecting(to id: UUID) -> ConnectionStateMachine {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.remembered(id)))
        return machine
    }

    /// A machine whose link to `id` is usable.
    func connected(to id: UUID) -> ConnectionStateMachine {
        var machine = connecting(to: id)
        _ = machine.handle(.didConnect(id))
        _ = machine.handle(.linkReady(id))
        return machine
    }

    // MARK: - Starting an attempt

    @Test func selectingStartsAnAttempt() {
        var machine = ConnectionStateMachine()
        #expect(machine.handle(.selected) == [.beginAttempt])
        #expect(machine.isSelected)
        #expect(machine.failedAttempts == 0)
    }

    @Test func scansWhenNothingIsKnown() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        let actions = machine.handle(.attempt(.none))
        #expect(actions == [.cancelTimer(.retry), .scan, .startTimer(.watchdog, .seconds(10))])
        #expect(machine.phase == .scanning)
    }

    @Test func connectsToTheRememberedPeripheral() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        let actions = machine.handle(.attempt(.remembered(a)))
        #expect(actions == [.connect(a), .cancelTimer(.retry), .startTimer(.watchdog, .seconds(10))])
        #expect(machine.phase == .connecting)
        #expect(machine.current == a)
    }

    @Test func alsoScansWhenTheRememberedIdentifierKeepsFailing() {
        var machine = connecting(to: a)
        _ = machine.handle(.didFailToConnect(a))
        _ = machine.handle(.timerFired(.retry))
        _ = machine.handle(.attempt(.remembered(a)))
        _ = machine.handle(.didFailToConnect(a))
        #expect(machine.failedAttempts == 2)

        let actions = machine.handle(.attempt(.remembered(a)))
        #expect(actions.first == .scan)
        #expect(actions.contains(.connect(a)))
    }

    @Test func ignoresAnAttemptAfterDeselecting() {
        var machine = connecting(to: a)
        _ = machine.handle(.deselected)
        #expect(machine.handle(.attempt(.remembered(a))).isEmpty)
    }

    // MARK: - Failing to connect

    @Test func failedConnectClearsThePeripheralAndRetries() {
        var machine = connecting(to: a)
        let actions = machine.handle(.didFailToConnect(a))
        #expect(actions == [.cancelTimer(.watchdog), .startTimer(.retry, .seconds(1))])
        #expect(machine.current == nil)
        #expect(machine.failedAttempts == 1)

        // The retry has to start a new attempt; it used to be skipped because the failed
        // peripheral was still set, leaving the app on "Connecting…".
        #expect(machine.handle(.timerFired(.retry)) == [.beginAttempt])
    }

    @Test func retryDelaysDoubleThenGiveUp() {
        var machine = connecting(to: a)
        var delays: [Duration] = []
        for _ in 0..<4 {
            let actions = machine.handle(.didFailToConnect(a))
            if case .startTimer(.retry, let delay)? = actions.last { delays.append(delay) }
            _ = machine.handle(.timerFired(.retry))
            _ = machine.handle(.attempt(.remembered(a)))
        }
        #expect(delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])

        let actions = machine.handle(.didFailToConnect(a))
        #expect(actions == [.cancelTimer(.watchdog), .giveUp])
        #expect(machine.failedAttempts == ConnectionStateMachine.maxFailedAttempts)
    }

    @Test func retryTimerIsIgnoredWhileAPeripheralIsCurrent() {
        var machine = connecting(to: a)
        #expect(machine.handle(.timerFired(.retry)).isEmpty)
    }

    // MARK: - Stale callbacks

    @Test func ignoresAFailureFromAReplacedPeripheral() {
        var machine = connecting(to: a)
        // A scan finds the headphones under a new identifier, replacing the stale one.
        let actions = machine.handle(.discovered(b, .exact))
        #expect(actions.contains(.cancel(a)))
        #expect(actions.contains(.connect(b)))

        #expect(machine.handle(.didFailToConnect(a)).isEmpty)
        #expect(machine.handle(.didDisconnect(a)).isEmpty)
        #expect(machine.current == b)
        #expect(machine.failedAttempts == 0)
        #expect(machine.phase == .connecting)
    }

    @Test func ignoresCallbacksForAPeripheralThatWasNeverCurrent() {
        var machine = connecting(to: a)
        #expect(machine.handle(.didConnect(b)).isEmpty)
        #expect(machine.handle(.linkReady(b)).isEmpty)
        #expect(machine.phase == .connecting)
    }

    @Test func ignoresACancelledLinkReportingReady() {
        var machine = connecting(to: a)
        _ = machine.handle(.discovered(b, .exact))
        #expect(machine.handle(.linkReady(a)).isEmpty)
        #expect(machine.phase == .connecting)
    }

    // MARK: - Watchdog

    @Test func watchdogRestartsAnAttemptThatHangs() {
        var machine = connecting(to: a)
        let actions = machine.handle(.timerFired(.watchdog))
        #expect(actions == [
            .stopScan, .cancel(a),
            .cancelTimer(.watchdog), .cancelTimer(.retry), .cancelTimer(.fallback),
            .startTimer(.retry, .seconds(1)),
        ])
        #expect(machine.current == nil)
        #expect(machine.failedAttempts == 1)
    }

    @Test func watchdogRestartsAScanThatFindsNothing() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        let actions = machine.handle(.timerFired(.watchdog))
        #expect(actions.contains(.stopScan))
        #expect(actions.last == .startTimer(.retry, .seconds(1)))
        #expect(machine.failedAttempts == 1)
    }

    @Test func linkThatConnectsButNeverShowsServicesStillCountsAsFailed() {
        var machine = connecting(to: a)
        #expect(machine.handle(.didConnect(a)) == [.discoverServices(a)])
        _ = machine.handle(.timerFired(.watchdog))
        #expect(machine.failedAttempts == 1)
    }

    @Test func watchdogGivesUpAfterTheLastAttempt() {
        var machine = connecting(to: a)
        for _ in 0..<(ConnectionStateMachine.maxFailedAttempts - 1) {
            _ = machine.handle(.timerFired(.watchdog))
            _ = machine.handle(.timerFired(.retry))
            _ = machine.handle(.attempt(.remembered(a)))
        }
        #expect(machine.handle(.timerFired(.watchdog)).last == .giveUp)
    }

    @Test func watchdogIsIgnoredOnceConnected() {
        var machine = connected(to: a)
        #expect(machine.handle(.timerFired(.watchdog)).isEmpty)
        #expect(machine.phase == .connected)
    }

    // MARK: - Connected

    @Test func usableLinkResetsFailuresAndStopsTheWatchdog() {
        var machine = connecting(to: a)
        _ = machine.handle(.didFailToConnect(a))
        _ = machine.handle(.timerFired(.retry))
        _ = machine.handle(.attempt(.remembered(a)))
        _ = machine.handle(.didConnect(a))
        #expect(machine.failedAttempts == 1)

        #expect(machine.handle(.linkReady(a)) == [.cancelTimer(.watchdog)])
        #expect(machine.failedAttempts == 0)
        #expect(machine.phase == .connected)
    }

    @Test func droppedLinkRetriesAfterOneSecond() {
        var machine = connected(to: a)
        let actions = machine.handle(.didDisconnect(a))
        #expect(actions == [.cancelTimer(.watchdog), .startTimer(.retry, .seconds(1))])
        #expect(machine.current == nil)
        #expect(machine.phase == .connecting)
    }

    // MARK: - Fallback match

    @Test func waitsForAnExactMatchBeforeUsingAnotherJBL() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))

        #expect(machine.handle(.discovered(a, .fallback)) == [.startTimer(.fallback, .seconds(3))])
        // A second fallback doesn't restart the wait.
        #expect(machine.handle(.discovered(b, .fallback)).isEmpty)
        #expect(machine.current == nil)

        let actions = machine.handle(.timerFired(.fallback))
        #expect(actions.first == .stopScan)
        #expect(actions.contains(.connect(a)))
        #expect(machine.current == a)
    }

    @Test func exactMatchBeatsAPendingFallback() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        _ = machine.handle(.discovered(a, .fallback))

        let actions = machine.handle(.discovered(b, .exact))
        #expect(actions.prefix(2) == [.cancelTimer(.fallback), .stopScan])
        #expect(actions.contains(.connect(b)))

        // If the cancelled timer still fires, it must not replace the exact match.
        #expect(machine.handle(.timerFired(.fallback)).isEmpty)
        #expect(machine.current == b)
    }

    @Test func exactMatchAfterTheFallbackWasChosenReplacesIt() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        _ = machine.handle(.discovered(a, .fallback))
        _ = machine.handle(.timerFired(.fallback))

        let actions = machine.handle(.discovered(b, .exact))
        #expect(actions.contains(.cancel(a)))
        #expect(actions.contains(.connect(b)))
    }

    @Test func rediscoveringTheCurrentPeripheralDoesNotReconnect() {
        var machine = connecting(to: a)
        #expect(machine.handle(.discovered(a, .exact)) == [.cancelTimer(.fallback), .stopScan])
        #expect(machine.current == a)
    }

    @Test func unrelatedDevicesAreIgnored() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        #expect(machine.handle(.discovered(a, .none)).isEmpty)
    }

    // MARK: - Deselecting

    @Test func deselectingDropsTheLinkAndEveryTimer() {
        var machine = connected(to: a)
        let actions = machine.handle(.deselected)
        #expect(actions == [
            .stopScan, .cancel(a),
            .cancelTimer(.watchdog), .cancelTimer(.retry), .cancelTimer(.fallback),
        ])
        #expect(machine.phase == .idle)
        #expect(machine.current == nil)
        #expect(!machine.isSelected)
    }

    @Test func eventsAfterDeselectingDoNothing() {
        var machine = connecting(to: a)
        _ = machine.handle(.deselected)
        #expect(machine.handle(.didDisconnect(a)).isEmpty)
        #expect(machine.handle(.timerFired(.watchdog)).isEmpty)
        #expect(machine.handle(.timerFired(.retry)).isEmpty)
        #expect(machine.handle(.discovered(b, .exact)).isEmpty)
    }

    @Test func selectingAgainStartsFromScratch() {
        var machine = connecting(to: a)
        _ = machine.handle(.didFailToConnect(a))
        _ = machine.handle(.deselected)
        #expect(machine.handle(.selected) == [.beginAttempt])
        #expect(machine.failedAttempts == 0)
    }
}

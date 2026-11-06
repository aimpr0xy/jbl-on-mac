import Foundation
@testable import JblOnMac
import Testing

struct ConnectionStateMachineTests {
    let first = UUID()
    let second = UUID()

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
        let actions = machine.handle(.attempt(.remembered(first)))
        #expect(actions == [
            .scan, .connect(first), .cancelTimer(.retry), .startTimer(.watchdog, .seconds(10))
        ])
        #expect(machine.phase == .connecting)
        #expect(machine.current == first)
    }

    @Test func scansFromTheFirstRememberedAttemptInCaseTheIdentifierIsStale() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        #expect(machine.failedAttempts == 0)
        #expect(machine.handle(.attempt(.remembered(first))).first == .scan)
    }

    @Test func switchesToTheNewIdentifierWithoutWaitingForTheWatchdog() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.remembered(first)))

        let actions = machine.handle(.discovered(second, .exact))
        #expect(actions.contains(.cancel(first)))
        #expect(actions.contains(.connect(second)))
        #expect(machine.current == second)
        #expect(machine.failedAttempts == 0)
    }

    @Test func stopsScanningWhenTheRememberedIdentifierWins() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.remembered(first)))
        _ = machine.handle(.didConnect(first))
        #expect(machine.handle(.linkReady(first)).first == .stopScan)
    }

    @Test func ignoresAnAttemptAfterDeselecting() {
        var machine = connecting(to: first)
        _ = machine.handle(.deselected)
        #expect(machine.handle(.attempt(.remembered(first))).isEmpty)
    }

    // MARK: - Failing to connect

    @Test func failedConnectClearsThePeripheralAndRetries() {
        var machine = connecting(to: first)
        let actions = machine.handle(.didFailToConnect(first))
        #expect(actions == [.cancelTimer(.watchdog), .startTimer(.retry, .seconds(1))])
        #expect(machine.current == nil)
        #expect(machine.failedAttempts == 1)

        // The retry has to start a new attempt; it used to be skipped because the failed
        // peripheral was still set, leaving the app on "Connecting…".
        #expect(machine.handle(.timerFired(.retry)) == [.beginAttempt])
    }

    @Test func retryDelaysDoubleThenGiveUp() {
        var machine = connecting(to: first)
        var delays: [Duration] = []
        for _ in 0 ..< 4 {
            let actions = machine.handle(.didFailToConnect(first))
            if case let .startTimer(.retry, delay)? = actions.last {
                delays.append(delay)
            }
            _ = machine.handle(.timerFired(.retry))
            _ = machine.handle(.attempt(.remembered(first)))
        }
        #expect(delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])

        let actions = machine.handle(.didFailToConnect(first))
        #expect(actions == [.cancelTimer(.watchdog), .giveUp])
        #expect(machine.failedAttempts == ConnectionStateMachine.maxFailedAttempts)
    }

    @Test func retryTimerIsIgnoredWhileAPeripheralIsCurrent() {
        var machine = connecting(to: first)
        #expect(machine.handle(.timerFired(.retry)).isEmpty)
    }

    // MARK: - Stale callbacks

    @Test func ignoresAFailureFromAReplacedPeripheral() {
        var machine = connecting(to: first)
        // A scan finds the headphones under a new identifier, replacing the stale one.
        let actions = machine.handle(.discovered(second, .exact))
        #expect(actions.contains(.cancel(first)))
        #expect(actions.contains(.connect(second)))

        #expect(machine.handle(.didFailToConnect(first)).isEmpty)
        #expect(machine.handle(.didDisconnect(first)).isEmpty)
        #expect(machine.current == second)
        #expect(machine.failedAttempts == 0)
        #expect(machine.phase == .connecting)
    }

    @Test func ignoresCallbacksForAPeripheralThatWasNeverCurrent() {
        var machine = connecting(to: first)
        #expect(machine.handle(.didConnect(second)).isEmpty)
        #expect(machine.handle(.linkReady(second)).isEmpty)
        #expect(machine.phase == .connecting)
    }

    @Test func ignoresACancelledLinkReportingReady() {
        var machine = connecting(to: first)
        _ = machine.handle(.discovered(second, .exact))
        #expect(machine.handle(.linkReady(first)).isEmpty)
        #expect(machine.phase == .connecting)
    }

    // MARK: - Watchdog

    @Test func watchdogRestartsAnAttemptThatHangs() {
        var machine = connecting(to: first)
        let actions = machine.handle(.timerFired(.watchdog))
        #expect(actions == [
            .stopScan, .cancel(first),
            .cancelTimer(.watchdog), .cancelTimer(.retry), .cancelTimer(.fallback),
            .startTimer(.retry, .seconds(1))
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
        var machine = connecting(to: first)
        #expect(machine.handle(.didConnect(first)) == [.discoverServices(first)])
        _ = machine.handle(.timerFired(.watchdog))
        #expect(machine.failedAttempts == 1)
    }

    @Test func watchdogGivesUpAfterTheLastAttempt() {
        var machine = connecting(to: first)
        for _ in 0 ..< (ConnectionStateMachine.maxFailedAttempts - 1) {
            _ = machine.handle(.timerFired(.watchdog))
            _ = machine.handle(.timerFired(.retry))
            _ = machine.handle(.attempt(.remembered(first)))
        }
        #expect(machine.handle(.timerFired(.watchdog)).last == .giveUp)
    }

    @Test func watchdogIsIgnoredOnceConnected() {
        var machine = connected(to: first)
        #expect(machine.handle(.timerFired(.watchdog)).isEmpty)
        #expect(machine.phase == .connected)
    }

    // MARK: - Connected

    @Test func usableLinkResetsFailuresAndStopsTheWatchdog() {
        var machine = connecting(to: first)
        _ = machine.handle(.didFailToConnect(first))
        _ = machine.handle(.timerFired(.retry))
        _ = machine.handle(.attempt(.remembered(first)))
        _ = machine.handle(.didConnect(first))
        #expect(machine.failedAttempts == 1)

        #expect(machine.handle(.linkReady(first)) == [.stopScan, .cancelTimer(.watchdog)])
        #expect(machine.failedAttempts == 0)
        #expect(machine.phase == .connected)
    }

    @Test func droppedLinkRetriesAfterOneSecond() {
        var machine = connected(to: first)
        let actions = machine.handle(.didDisconnect(first))
        #expect(actions == [.cancelTimer(.watchdog), .startTimer(.retry, .seconds(1))])
        #expect(machine.current == nil)
        #expect(machine.phase == .connecting)
    }

    // MARK: - Fallback match

    @Test func waitsForAnExactMatchBeforeUsingAnotherJBL() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))

        #expect(machine.handle(.discovered(first, .fallback)) == [.startTimer(.fallback, .seconds(3))])
        // A second fallback doesn't restart the wait.
        #expect(machine.handle(.discovered(second, .fallback)).isEmpty)
        #expect(machine.current == nil)

        let actions = machine.handle(.timerFired(.fallback))
        #expect(actions.first == .stopScan)
        #expect(actions.contains(.connect(first)))
        #expect(machine.current == first)
    }

    @Test func exactMatchBeatsAPendingFallback() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        _ = machine.handle(.discovered(first, .fallback))

        let actions = machine.handle(.discovered(second, .exact))
        #expect(actions.prefix(2) == [.cancelTimer(.fallback), .stopScan])
        #expect(actions.contains(.connect(second)))

        // If the cancelled timer still fires, it must not replace the exact match.
        #expect(machine.handle(.timerFired(.fallback)).isEmpty)
        #expect(machine.current == second)
    }

    @Test func exactMatchAfterTheFallbackWasChosenReplacesIt() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        _ = machine.handle(.discovered(first, .fallback))
        _ = machine.handle(.timerFired(.fallback))

        let actions = machine.handle(.discovered(second, .exact))
        #expect(actions.contains(.cancel(first)))
        #expect(actions.contains(.connect(second)))
    }

    @Test func rediscoveringTheCurrentPeripheralDoesNotReconnect() {
        var machine = connecting(to: first)
        #expect(machine.handle(.discovered(first, .exact)) == [.cancelTimer(.fallback), .stopScan])
        #expect(machine.current == first)
    }

    @Test func unrelatedDevicesAreIgnored() {
        var machine = ConnectionStateMachine()
        _ = machine.handle(.selected)
        _ = machine.handle(.attempt(.none))
        #expect(machine.handle(.discovered(first, .none)).isEmpty)
    }

    // MARK: - Deselecting

    @Test func deselectingDropsTheLinkAndEveryTimer() {
        var machine = connected(to: first)
        let actions = machine.handle(.deselected)
        #expect(actions == [
            .stopScan, .cancel(first),
            .cancelTimer(.watchdog), .cancelTimer(.retry), .cancelTimer(.fallback)
        ])
        #expect(machine.phase == .idle)
        #expect(machine.current == nil)
        #expect(!machine.isSelected)
    }

    @Test func eventsAfterDeselectingDoNothing() {
        var machine = connecting(to: first)
        _ = machine.handle(.deselected)
        #expect(machine.handle(.didDisconnect(first)).isEmpty)
        #expect(machine.handle(.timerFired(.watchdog)).isEmpty)
        #expect(machine.handle(.timerFired(.retry)).isEmpty)
        #expect(machine.handle(.discovered(second, .exact)).isEmpty)
    }

    @Test func selectingAgainStartsFromScratch() {
        var machine = connecting(to: first)
        _ = machine.handle(.didFailToConnect(first))
        _ = machine.handle(.deselected)
        #expect(machine.handle(.selected) == [.beginAttempt])
        #expect(machine.failedAttempts == 0)
    }
}

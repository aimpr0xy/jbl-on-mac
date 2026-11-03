import Foundation

/// Decides what the link to the selected headphones should do next. It knows nothing about Core
/// Bluetooth: `HeadphoneController` reports what happened as an `Event` and carries out the
/// `Action`s that come back, so every retry, timeout and fallback decision can be tested without
/// a radio or a real clock.
///
/// Peripherals are identified by their Core Bluetooth identifier. Any callback for a peripheral
/// other than the current one belongs to an attempt that was already replaced or cancelled, and
/// is ignored.
struct ConnectionStateMachine {
    enum Phase: Equatable {
        case idle
        case scanning
        case connecting
        case connected
    }

    enum Timer: Hashable {
        /// Any attempt can hang forever, so one that isn't connected after this long is restarted.
        case watchdog
        /// The backoff delay before the next attempt.
        case retry
        /// How long to wait for an exact name match before settling for another JBL.
        case fallback
    }

    /// What the controller found when it looked for the headphones.
    enum Lookup: Equatable {
        /// The LE identifier remembered from the last successful connection.
        case remembered(UUID)
        /// A peripheral the system already holds a connection to.
        case alreadyConnected(UUID)
        case none
    }

    /// How well an advertised name matches the selected device.
    enum NameMatch: Equatable {
        case exact
        /// Some other JBL; only used if no exact match turns up shortly after.
        case fallback
        case none
    }

    enum Event: Equatable {
        case selected
        case deselected
        case attempt(Lookup)
        case discovered(UUID, NameMatch)
        case didConnect(UUID)
        case didFailToConnect(UUID)
        case didDisconnect(UUID)
        /// The write and notify characteristics were found, so the link is usable.
        case linkReady(UUID)
        case timerFired(Timer)
    }

    enum Action: Equatable {
        /// Look for the headphones, then report the result as `.attempt`.
        case beginAttempt
        case connect(UUID)
        case scan
        case stopScan
        case cancel(UUID)
        case discoverServices(UUID)
        case startTimer(Timer, Duration)
        case cancelTimer(Timer)
        /// Too many attempts failed in a row; stop retrying.
        case giveUp
    }

    static let maxFailedAttempts = 5
    static let watchdogDuration = Duration.seconds(10)
    static let fallbackDelay = Duration.seconds(3)

    private(set) var phase: Phase = .idle
    private(set) var isSelected = false
    /// The peripheral being connected or connected. Nil while scanning or waiting to retry.
    private(set) var current: UUID?
    /// Failed attempts since the last usable link; drives the retry backoff.
    private(set) var failedAttempts = 0
    private var fallback: UUID?

    mutating func handle(_ event: Event) -> [Action] {
        switch event {
        case .selected:
            isSelected = true
            failedAttempts = 0
            return [.beginAttempt]

        case .deselected:
            isSelected = false
            phase = .idle
            return dropLink()

        case .attempt(let lookup):
            guard isSelected else { return [] }
            switch lookup {
            case .remembered(let id):
                // The identifier may be stale (the headphones can change their LE address), so
                // after a couple of failures also scan for a new one.
                return (failedAttempts >= 2 ? [.scan] : []) + connect(to: id)
            case .alreadyConnected(let id):
                return connect(to: id)
            case .none:
                phase = .scanning
                return [.cancelTimer(.retry), .scan, .startTimer(.watchdog, Self.watchdogDuration)]
            }

        case .discovered(let id, let match):
            guard isSelected else { return [] }
            switch match {
            case .none:
                return []
            case .exact:
                fallback = nil
                return [.cancelTimer(.fallback), .stopScan] + connect(to: id)
            case .fallback:
                guard fallback == nil else { return [] }
                fallback = id
                return [.startTimer(.fallback, Self.fallbackDelay)]
            }

        case .didConnect(let id):
            guard id == current else { return [] }
            return [.discoverServices(id)]

        case .didFailToConnect(let id):
            guard id == current else { return [] }
            failedAttempts += 1
            current = nil
            return [.cancelTimer(.watchdog)] + retry()

        case .didDisconnect(let id):
            guard id == current else { return [] }
            current = nil
            return [.cancelTimer(.watchdog)] + retry()

        case .linkReady(let id):
            guard id == current else { return [] }
            // Only now does the attempt count as a success; a link that connects but never shows
            // its services should still count toward giving up.
            failedAttempts = 0
            phase = .connected
            return [.cancelTimer(.watchdog)]

        case .timerFired(.watchdog):
            guard isSelected, phase != .connected else { return [] }
            failedAttempts += 1
            return dropLink() + retry()

        case .timerFired(.retry):
            guard isSelected, current == nil else { return [] }
            return [.beginAttempt]

        case .timerFired(.fallback):
            guard isSelected, current == nil, let id = fallback else { return [] }
            fallback = nil
            return [.stopScan] + connect(to: id)
        }
    }

    /// Starts connecting to a peripheral, replacing a different one that was still in progress.
    private mutating func connect(to id: UUID) -> [Action] {
        if id == current { return [] }
        var actions: [Action] = []
        if let previous = current { actions.append(.cancel(previous)) }
        current = id
        fallback = nil
        phase = .connecting
        return actions + [.connect(id), .cancelTimer(.retry), .startTimer(.watchdog, Self.watchdogDuration)]
    }

    /// Stops scanning and cancels the current link and every timer.
    private mutating func dropLink() -> [Action] {
        var actions: [Action] = [.stopScan]
        if let id = current { actions.append(.cancel(id)) }
        current = nil
        fallback = nil
        return actions + [.cancelTimer(.watchdog), .cancelTimer(.retry), .cancelTimer(.fallback)]
    }

    /// Tries again after a failure or a dropped link, as long as a device is selected. The delay
    /// doubles with each failed attempt (1, 2, 4, 8 s); after `maxFailedAttempts` it gives up.
    private mutating func retry() -> [Action] {
        guard isSelected else { return [] }
        guard failedAttempts < Self.maxFailedAttempts else { return [.giveUp] }
        phase = .connecting
        return [.startTimer(.retry, .seconds(1 << max(failedAttempts - 1, 0)))]
    }
}

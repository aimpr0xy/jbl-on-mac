/// Everything between "the UI changed a setting" and "bytes on the wire": which write a result
/// belongs to, the chunked equalizer upload and download of the Tune 230NC, and the timeout that
/// keeps a transfer that stalls from blocking later ones. It knows nothing about Core Bluetooth:
/// `HeadphoneController` reports what happened as an `Event` and carries out the `Action`s that
/// come back, like it does for `ConnectionStateMachine`.
struct CommandPipeline: Equatable {
    enum Event: Equatable {
        case send(JBLCommand)
        /// Tune 230NC: write a preset as a chunked upload, or queue it behind the running one.
        case uploadEqualizer(EqualizerPreset)
        /// The oldest outstanding write finished; the text describes the error, if there was one.
        case writeCompleted(error: String?)
        case notified([UInt8])
        case linkDropped
        case timerFired
    }

    enum Action: Equatable {
        case write(JBLCommand)
        /// A decoded reply for the controller to copy into the observable state.
        case apply(JBLReply)
        /// A finished equalizer download: the preset it matches, nil for a custom curve.
        case equalizerDownloaded(EqualizerPreset?)
        /// Starts the timer, replacing a running one, and reports it as `.timerFired` when it ends.
        case startTimer(Duration)
        case cancelTimer
        case log(String, isError: Bool)
    }

    /// How long an upload or download may stay silent before it is given up on.
    static let transferTimeout = Duration.seconds(5)

    /// Commands written but not yet acknowledged, oldest first; write-with-response results
    /// arrive in order, and the callback doesn't say which command it is for.
    private(set) var pendingWrites: [JBLCommand] = []
    /// Packets of the equalizer upload still to send, each after the previous one is acked.
    /// Nil while no upload is running.
    private(set) var uploadRemaining: [JBLCommand]?
    /// A preset picked while an upload was running, sent once it finishes.
    private(set) var queuedEqualizer: EqualizerPreset?
    /// Bytes of the chunked reply being received. Nil while none is.
    private(set) var downloadBuffer: [UInt8]?
    /// Whether the upload running now is the retry of a queued preset after a timeout.
    private var isRetrying = false

    private var isTransferring: Bool {
        uploadRemaining != nil || downloadBuffer != nil
    }

    /// `presets` are the equalizer presets of the selected model, to name a downloaded curve.
    mutating func handle(_ event: Event, presets: [EqualizerPreset] = []) -> [Action] {
        switch event {
        case let .send(command):
            [transmit(command)]
        case let .uploadEqualizer(preset):
            upload(preset)
        case let .writeCompleted(error):
            writeCompleted(error: error)
        case let .notified(bytes):
            notified(bytes, presets: presets)
        case .linkDropped:
            linkDropped()
        case .timerFired:
            timerFired()
        }
    }

    // MARK: - Writing

    private mutating func transmit(_ command: JBLCommand) -> Action {
        pendingWrites.append(command)
        return .write(command)
    }

    /// The UI is updated optimistically, so a failed write must be undone: ask the headphones
    /// for the real state.
    private mutating func writeCompleted(error: String?) -> [Action] {
        guard !pendingWrites.isEmpty else { return [] }
        let command = pendingWrites.removeFirst()
        guard let error else { return [] }
        var actions = [Action.log("write failed for \(String(describing: command)): \(error)", isError: true)]
        // The rest of an upload is useless once one of its packets is lost.
        if command.refreshQuery == .queryEqualizerCurve {
            abandonUpload()
            actions.append(transferTimer())
        }
        if let query = command.refreshQuery {
            actions.append(transmit(query))
        }
        return actions
    }

    // MARK: - Uploading

    private mutating func upload(_ preset: EqualizerPreset) -> [Action] {
        guard uploadRemaining == nil else {
            queuedEqualizer = preset
            return []
        }
        var packets = JBLCommand.equalizerUpload(preset)
        let first = transmit(packets.removeFirst())
        uploadRemaining = packets
        return [first, transferTimer()]
    }

    private mutating func abandonUpload() {
        uploadRemaining = nil
        queuedEqualizer = nil
        isRetrying = false
    }

    /// Sends the next packet once the headphones acked the previous one.
    private mutating func uploadPacketAcknowledged() -> [Action] {
        guard var remaining = uploadRemaining else { return [] }
        guard !remaining.isEmpty else {
            uploadRemaining = nil
            isRetrying = false
            guard let next = queuedEqualizer else { return [transferTimer()] }
            queuedEqualizer = nil
            return upload(next)
        }
        let packet = transmit(remaining.removeFirst())
        uploadRemaining = remaining
        return [packet, transferTimer()]
    }

    // MARK: - Receiving

    private mutating func notified(_ bytes: [UInt8], presets: [EqualizerPreset]) -> [Action] {
        // Chunks of a Tune 230NC download are raw `<index> <bytes…>`, not frames. Each is acked.
        if downloadBuffer != nil, let index = bytes.first, index != 0xAA {
            downloadBuffer?.append(contentsOf: bytes.dropFirst())
            return [transmit(.acknowledgeDownload), transferTimer()]
        }
        var actions: [Action] = []
        for reply in JBLReply.decode(bytes) {
            actions += react(to: reply, presets: presets)
        }
        return actions
    }

    private mutating func react(to reply: JBLReply, presets: [EqualizerPreset]) -> [Action] {
        switch reply {
        case let .acknowledged(group, status) where group == 0x41:
            acknowledged(status: status)
        case .downloadStarted:
            downloadStarted()
        case .downloadFinished:
            finishDownload(presets: presets)
        default:
            [.apply(reply)]
        }
    }

    private mutating func acknowledged(status: UInt8) -> [Action] {
        if status == 0 {
            return uploadPacketAcknowledged()
        }
        // Rejected: stop the upload and show what the headphones actually use.
        abandonUpload()
        return [
            .log("equalizer upload rejected with status \(status)", isError: true),
            transmit(.queryEqualizerCurve),
            transferTimer()
        ]
    }

    private mutating func downloadStarted() -> [Action] {
        downloadBuffer = []
        return [transmit(.acknowledgeDownload), transferTimer()]
    }

    private mutating func finishDownload(presets: [EqualizerPreset]) -> [Action] {
        // Nil for a curve that isn't one of the presets, such as a custom one.
        var preset: EqualizerPreset?
        if let buffer = downloadBuffer, let gains = JBLReply.equalizerGains(fromDownload: buffer) {
            preset = presets.first { $0.tune230NCGains == gains }
        }
        downloadBuffer = nil
        return [.equalizerDownloaded(preset), transmit(.acknowledgeDownload), transferTimer()]
    }

    // MARK: - Timeout and link loss

    /// Restarts the timeout while a transfer is running, and stops it once none is.
    private func transferTimer() -> Action {
        isTransferring ? .startTimer(Self.transferTimeout) : .cancelTimer
    }

    /// A transfer that never finishes would block every later one, so give up on it, show what
    /// the headphones actually use, and retry a preset that was waiting, once.
    private mutating func timerFired() -> [Action] {
        guard isTransferring else { return [] }
        let retry = isRetrying ? nil : queuedEqualizer
        abandonUpload()
        downloadBuffer = nil
        var actions = [
            Action.log("equalizer transfer timed out", isError: true),
            transmit(.queryEqualizerCurve)
        ]
        if let retry {
            actions += upload(retry)
            isRetrying = true
        } else {
            actions.append(.cancelTimer)
        }
        return actions
    }

    private mutating func linkDropped() -> [Action] {
        let wasTransferring = isTransferring
        self = CommandPipeline()
        return wasTransferring ? [.cancelTimer] : []
    }
}

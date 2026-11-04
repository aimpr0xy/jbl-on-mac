import CoreBluetooth
import Foundation
import os

/// Running the command pipeline.
extension HeadphoneController {
    /// Feeds an event to the pipeline and carries out what it asks for.
    func run(_ event: CommandPipeline.Event) {
        for action in pipeline.handle(event, presets: model.equalizerPresets) {
            perform(action)
        }
    }

    private func perform(_ action: CommandPipeline.Action) {
        switch action {
        case let .write(command):
            write(command)
        case let .apply(reply):
            apply(reply)
        case let .equalizerDownloaded(preset):
            // Nothing to show for a curve that isn't one of the presets, such as a custom one.
            if let preset {
                state.equalizer = preset
            }
        case let .startTimer(duration):
            startTransferTimer(duration)
        case .cancelTimer:
            transferTimer?.cancel()
            transferTimer = nil
        case let .log(message, isError):
            log(message, level: isError ? .error : .default)
        }
    }

    private func write(_ command: JBLCommand) {
        let bytes = command.bytes
        log(
            "sent \(String(describing: command)): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))",
            level: .debug
        )
        guard let peripheral, let writeCharacteristic else { return }
        peripheral.writeValue(Data(bytes), for: writeCharacteristic, type: .withResponse)
    }

    private func startTransferTimer(_ duration: Duration) {
        transferTimer?.cancel()
        transferTimer = Task.afterDelay(duration) { [weak self] in
            guard let self else { return }
            transferTimer = nil
            run(.timerFired)
        }
    }
}

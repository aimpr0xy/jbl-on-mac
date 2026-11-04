/// The commands the UI can send to the selected headphones.
extension HeadphoneController {
    /// Whether the BLE link is ready for writes, and the model is one we know how to write to.
    private var canSend: Bool {
        peripheral != nil && writeCharacteristic != nil && model.allowsWrites
    }

    /// Sends the ambient sound command for the given mode.
    func select(_ mode: ListeningMode) {
        guard canSend else { return }
        send(.setListeningMode(mode))
        state.mode = mode
    }

    /// Sets the strength (1...7) of noise canceling or ambient aware.
    func setLevel(_ level: Int, for mode: ListeningMode) {
        guard canSend else { return }
        let level = min(max(level, 1), 7)
        switch mode {
        case .noiseCanceling:
            guard state.noiseCancelingLevel != level else { return }
            state.noiseCancelingLevel = level
        case .ambientAware:
            guard state.ambientAwareLevel != level else { return }
            state.ambientAwareLevel = level
        case .talkThru, .off:
            return
        }
        send(.setLevel(mode, level))
    }

    /// Sends the spatial audio command for the given mode.
    func select(_ spatial: SpatialAudioMode) {
        guard canSend else { return }
        send(.setSpatialAudio(spatial))
        state.spatialMode = spatial
    }

    /// Sends the smart audio and video command for the given mode.
    func select(_ smart: SmartAudioMode) {
        guard canSend else { return }
        send(model.smartAudioCommand(smart))
        state.smartMode = smart
    }

    /// Sets the left / right balance (-16 left ... 16 right).
    func setBalance(_ value: Int) {
        guard canSend else { return }
        let value = min(max(value, -16), 16)
        guard state.balance != value else { return }
        state.balance = value
        send(.setBalance(value))
    }

    /// Sends the equalizer command for the given preset.
    func select(_ preset: EqualizerPreset) {
        guard canSend else { return }
        state.equalizer = preset
        let packets = model.equalizerCommands(preset)
        if packets.count > 1 {
            upload(preset)
        } else {
            packets.forEach { send($0) }
        }
    }

    /// Starts the chunked write of a preset, or queues it behind the running one so two uploads
    /// don't interleave.
    private func upload(_ preset: EqualizerPreset) {
        guard uploadRemaining == nil else {
            queuedEqualizer = preset
            return
        }
        var packets = model.equalizerCommands(preset)
        send(packets.removeFirst())
        uploadRemaining = packets
    }

    /// Tune 230NC: sends the next upload packet once the headphones acked the previous one.
    func uploadPacketAcknowledged() {
        guard var remaining = uploadRemaining else { return }
        guard !remaining.isEmpty else {
            uploadRemaining = nil
            if let next = queuedEqualizer {
                queuedEqualizer = nil
                upload(next)
            }
            return
        }
        send(remaining.removeFirst())
        uploadRemaining = remaining
    }

    /// Sets what the touch controls of one earbud do.
    func select(_ control: GestureControl, for side: EarbudSide) {
        guard canSend else { return }
        send(model.gestureCommand(side, control, other: state.gestureControl(for: side.opposite)))
        if side == .left {
            state.leftGestureControl = control
        } else {
            state.rightGestureControl = control
        }
    }

    /// Turns the max volume limiter on or off.
    func setVolumeLimiter(_ enabled: Bool) {
        guard canSend else { return }
        state.volumeLimiterEnabled = enabled
        send(.setVolumeLimiter(enabled))
    }

    /// Turns the sound level optimizer on or off.
    func setSoundLevelOptimizer(_ enabled: Bool) {
        guard canSend else { return }
        state.soundLevelOptimizerEnabled = enabled
        send(.setSoundLevelOptimizer(enabled))
    }

    /// Sets the sound character used during calls.
    func select(_ setting: CallSoundSetting) {
        guard canSend else { return }
        state.callSoundSetting = setting
        send(.setCallSound(setting))
    }

    /// Sets how your voice sounds to the other side of a call.
    func select(_ setting: CallVoiceSetting) {
        guard canSend else { return }
        state.callVoiceSetting = setting
        send(.setCallVoice(setting))
    }

    /// Turns voice aware on or off, keeping the current level (mid until one is known).
    func setVoiceAware(enabled: Bool) {
        writeVoiceAware(enabled: enabled, level: state.voiceAwareLevel ?? .mid)
    }

    /// Sets the voice aware level and turns it on.
    func select(_ level: VoiceAwareLevel) {
        writeVoiceAware(enabled: true, level: level)
    }

    func writeVoiceAware(enabled: Bool, level: VoiceAwareLevel) {
        guard canSend else { return }
        state.voiceAwareEnabled = enabled
        state.voiceAwareLevel = level
        send(model.voiceAwareCommand(enabled: enabled, level: level))
    }
}

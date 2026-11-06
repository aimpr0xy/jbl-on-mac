/// The screens reachable once a device is connected. The device list is shown otherwise.
enum Screen: Hashable {
    case controls
    case ambientSound
    case smartAudio
    case spatialAudio
    case level(ListeningMode)
    case balance
    case equalizer
    case calls
    case callSound
    case callVoice
    case voiceAware
    case gestures(EarbudSide)
    case developerMode
}

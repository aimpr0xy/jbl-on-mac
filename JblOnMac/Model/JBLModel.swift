import Foundation

/// Which dialect of the JBL protocol a device speaks, picked from its Bluetooth name. Models we
/// haven't seen use the Tune Beam 2's, the most complete one documented in `JBLCommand`.
enum JBLModel: Equatable {
    case tuneBeam2
    /// Has no levels, spatial audio, balance, safe sound or call features other than voice aware,
    /// and uses its own commands for the rest.
    case tune230NC

    /// Matches names like "JBL TUNE230NC TWS" and its LE twin "JBL TUNE230NC TWS-LE".
    init(name: String) {
        let compact = name.uppercased().replacingOccurrences(of: " ", with: "")
        self = compact.contains("TUNE230NC") ? .tune230NC : .tuneBeam2
    }

    /// Everything asked for once notifications are on.
    var initialQueries: [JBLCommand] {
        switch self {
        case .tuneBeam2:
            [.queryListeningMode, .queryLevels, .queryEarbudBattery, .queryCaseBattery,
             .querySmartAudio, .querySpatialAudio, .queryBalance, .queryEqualizer,
             .queryVolumeLimiter, .queryCallFeature(id: 0x23), .queryCallFeature(id: 0x14),
             .queryCallFeature(id: 0x16), .queryCallFeature(id: 0x0D), .queryGestureControls]
        // The equalizer comes last: its reply is a chunked transfer, so the other replies don't
        // have to wait behind it.
        case .tune230NC:
            [.queryStatus, .queryCaseFirmware, .queryListeningMode, .queryBatteryLevels,
             .queryTune230NCSmartAudio, .queryTune230NCVoiceAware, .queryGestureControls,
             .queryEqualizerCurve]
        }
    }

    /// The query that makes the headphones report the active equalizer preset.
    var equalizerQuery: JBLCommand {
        self == .tune230NC ? .queryEqualizerCurve : .queryEqualizer
    }

    /// The presets the JBL app offers for this model, in the order shown.
    var equalizerPresets: [EqualizerPreset] {
        switch self {
        case .tuneBeam2: EqualizerPreset.allCases
        // Off is the flat curve the app sends when the equalizer is switched off.
        case .tune230NC: [.off, .jazz, .vocal, .bass, .club, .studio]
        }
    }

    /// The command that sets one earbud's touch controls. The Tune 230NC also wants the other
    /// earbud's last slot, so its current control is passed along (`.none` until reported).
    func gestureCommand(_ side: EarbudSide, _ control: GestureControl,
                        other: GestureControl?) -> JBLCommand {
        switch self {
        case .tuneBeam2: .setGestureControl(side, control)
        case .tune230NC: .setGestureControlWithOtherSide(side, control, other: other ?? .none)
        }
    }
}

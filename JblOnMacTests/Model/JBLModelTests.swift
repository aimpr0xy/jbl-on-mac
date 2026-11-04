import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

struct JBLModelTests {
    @Test(arguments: ["JBL TUNE230NC TWS", "JBL TUNE230NC TWS-LE", "JBL Tune 230NC TWS"])
    func recognizesTheTune230NC(_ name: String) {
        #expect(JBLModel(name: name) == .tune230NC)
    }

    @Test(arguments: ["JBL Tune Beam 2", "JBL Tune Beam 2-LE"])
    func recognizesTheTuneBeam2(_ name: String) {
        #expect(JBLModel(name: name) == .tuneBeam2)
    }

    @Test(arguments: ["JBL Flip 6", "JBL Charge 5", "JBL Live 770NC", "JBL"])
    func otherProductsAreUnknown(_ name: String) {
        #expect(JBLModel(name: name) == .unknown)
    }

    @Test func onlyKnownModelsAllowWrites() {
        #expect(JBLModel.tuneBeam2.allowsWrites)
        #expect(JBLModel.tune230NC.allowsWrites)
        #expect(!JBLModel.unknown.allowsWrites)
    }

    @Test(arguments: [JBLModel.tuneBeam2, .tune230NC, .unknown])
    func everyInitialQueryIsAQuery(_ model: JBLModel) {
        for query in model.initialQueries {
            #expect(query.refreshQuery == nil)
        }
    }

    @Test func initialQueriesPerModel() {
        #expect(JBLModel.tuneBeam2.initialQueries.count == 14)
        #expect(JBLModel.unknown.initialQueries.count == 14)
        #expect(JBLModel.tune230NC.initialQueries.count == 8)
        #expect(JBLModel.tune230NC.initialQueries.last == .queryEqualizerCurve)
    }

    @Test func equalizerQueryAndPresets() {
        #expect(JBLModel.tune230NC.equalizerQuery == .queryEqualizerCurve)
        #expect(JBLModel.tuneBeam2.equalizerQuery == .queryEqualizer)
        #expect(JBLModel.unknown.equalizerQuery == .queryEqualizer)
        #expect(JBLModel.tuneBeam2.equalizerPresets == EqualizerPreset.allCases)
        #expect(JBLModel.unknown.equalizerPresets == EqualizerPreset.allCases)
        #expect(JBLModel.tune230NC.equalizerPresets == [.off, .jazz, .vocal, .bass, .club, .studio])
    }

    @Test func smartAudioCommandPerModel() {
        #expect(JBLModel.tuneBeam2.smartAudioCommand(.video) == .setSmartAudio(.video))
        #expect(JBLModel.unknown.smartAudioCommand(.audio) == .setSmartAudio(.audio))
        #expect(JBLModel.tune230NC.smartAudioCommand(.video) == .setTune230NCSmartAudio(.video))
    }

    @Test func voiceAwareCommandPerModel() {
        #expect(JBLModel.tuneBeam2.voiceAwareCommand(enabled: false, level: .high)
            == .setVoiceAware(enabled: false, level: .high))
        #expect(JBLModel.unknown.voiceAwareCommand(enabled: true, level: .low)
            == .setVoiceAware(enabled: true, level: .low))
        #expect(JBLModel.tune230NC.voiceAwareCommand(enabled: true, level: .high)
            == .setTune230NCVoiceAware(.high))
        #expect(JBLModel.tune230NC.voiceAwareCommand(enabled: false, level: .high)
            == .setTune230NCVoiceAware(nil))
    }

    @Test func equalizerCommandsPerModel() {
        #expect(JBLModel.tuneBeam2.equalizerCommands(.jazz) == [.setEqualizer(.jazz)])
        #expect(JBLModel.unknown.equalizerCommands(.bass) == [.setEqualizer(.bass)])
        let upload = JBLModel.tune230NC.equalizerCommands(.jazz)
        #expect(upload == JBLCommand.equalizerUpload(.jazz))
        #expect(upload.count > 1)
    }

    @Test func onlyThe230NCForgetsItsLEIdentifier() {
        #expect(JBLModel.tuneBeam2.remembersLEIdentifier)
        #expect(JBLModel.unknown.remembersLEIdentifier)
        #expect(!JBLModel.tune230NC.remembersLEIdentifier)
    }

    @Test func advertisementMatchPerModel() {
        let model: [UInt8] = [0x96, 0xC1, 0x2E, 0x01]
        let idle: [UInt8] = [0x00, 0x00]
        #expect(JBLModel.tune230NC.advertisementMatch(serviceData: model) == .exact)
        #expect(JBLModel.tune230NC.advertisementMatch(serviceData: idle) == .fallback)
        #expect(JBLModel.tune230NC.advertisementMatch(serviceData: [0x01, 0x02, 0x03]) == nil)
        #expect(JBLModel.tuneBeam2.advertisementMatch(serviceData: model) == nil)
        #expect(JBLModel.unknown.advertisementMatch(serviceData: idle) == nil)
    }

    @Test func gestureCommandPerModel() {
        #expect(JBLModel.tuneBeam2.gestureCommand(.left, .volume, other: .playback)
            == .setGestureControl(.left, .volume))
        #expect(JBLModel.unknown.gestureCommand(.right, .none, other: nil)
            == .setGestureControl(.right, .none))
        #expect(JBLModel.tune230NC.gestureCommand(.left, .volume, other: .playback)
            == .setGestureControlWithOtherSide(.left, .volume, other: .playback))
        #expect(JBLModel.tune230NC.gestureCommand(.right, .volume, other: nil)
            == .setGestureControlWithOtherSide(.right, .volume, other: .none))
    }
}

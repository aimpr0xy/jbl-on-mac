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

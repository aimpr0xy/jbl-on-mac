import Testing
@testable import JblOnMac

/// Picking the dialect from a device's name, and what each dialect asks for on connect.
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
}

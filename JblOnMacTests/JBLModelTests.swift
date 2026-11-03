import Testing
@testable import JblOnMac

/// Picking the dialect from a device's name, and what each dialect asks for on connect.
struct JBLModelTests {
    @Test(arguments: ["JBL TUNE230NC TWS", "JBL TUNE230NC TWS-LE", "JBL Tune 230NC TWS"])
    func recognizesTheTune230NC(_ name: String) {
        #expect(JBLModel(name: name) == .tune230NC)
    }

    @Test(arguments: ["JBL Tune Beam 2", "JBL Tune Beam 2-LE", "JBL Live 770NC"])
    func otherModelsUseTheTuneBeam2Dialect(_ name: String) {
        #expect(JBLModel(name: name) == .tuneBeam2)
    }

    @Test(arguments: [JBLModel.tuneBeam2, .tune230NC])
    func everyInitialQueryIsAQuery(_ model: JBLModel) {
        for query in model.initialQueries {
            #expect(query.refreshQuery == nil)
        }
    }
}

/// A JBL product that is either nearby, paired, or connected over Bluetooth.
struct JBLDevice: Identifiable, Hashable {
    let name: String
    let address: String
    let isConnected: Bool
    var id: String {
        address
    }
}

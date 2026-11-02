import Foundation

/// The screens reachable once a device is connected. The device list is shown otherwise.
enum Screen: Hashable {
    case controls
    case level(ListeningMode)
    case balance
    case calls
}

import Testing

/// Parent of every suite that builds a `HeadphoneController` with `ControllerFixture`. They all
/// save and restore the same `UserDefaults` keys, so they must not run at the same time; a
/// serialized parent suite serializes all of its nested suites.
@Suite(.serialized)
enum ControllerSuite {}

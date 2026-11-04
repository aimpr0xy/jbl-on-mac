# JblOnMac

macOS menu bar app (SwiftUI, CoreBluetooth) for JBL headphones. Xcode project at the repo root
(`JblOnMac.xcodeproj/project.xcproj`), app in `JblOnMac/`, Swift Testing tests in `JblOnMacTests/`.
See `CONTRIBUTING.md` for the protocol and device workflow.

## Quality gates

Run `make check` before every commit. It runs the same steps as CI (`lint.yml`, `format.yml`, `test.yml`, `quality.yml` in `.github/workflows`):
SwiftLint, SwiftFormat `--lint`, build, tests, SwiftLint analyzer rules,
and Periphery. Run one step with `make lint`, `make format`, `make test`, and so on.
Tools: `brew install swiftlint swiftformat periphery`. If Xcode is not the selected developer directory,
set `DEVELOPER_DIR`.

### Limits (from `.swiftlint.yml`)

| Metric | Warning | Error |
| --- | --- | --- |
| Cyclomatic complexity | 8 | 10 |
| Function body length | 40 | 60 |
| Type body length | 250 | 400 |
| File length | 400 | 600 |
| Function parameters | 4 | 6 |

Nesting: 2 levels for types, 3 for functions. CI runs SwiftLint with `--strict`, so warnings fail too.
Split functions and types instead of fighting the limits.

### Rules

- No `!` force unwraps outside `JblOnMacTests`.
- No `swiftlint:disable` without a justification comment on the same or previous line.
- One test file per source file, mirroring the folders: `JblOnMac/Views/Controls/X.swift` is tested in
  `JblOnMacTests/Views/Controls/XTests.swift`, and `HeadphoneController+Foo.swift` in
  `HeadphoneController+FooTests.swift`. Never group several source files into one test file, and never
  name a test file after who or when wrote it. Extras: per-device protocol tests live in
  `JblOnMacTests/Protocol/Devices/` (one file per device), and shared helpers in `JblOnMacTests/Support/`.
  Suites that use `ControllerFixture` nest in `ControllerSuite`, which serializes them because they share
  `UserDefaults`. CI runs one test shard per top-level folder of `JblOnMacTests` (the matrix in `test.yml`);
  `make test TEST_SHARD=Views` runs one locally. The only source file without a test file is the `@main` entry point `App/JblOnMac.swift`.
- Every new function needs tests that assert behavior (inputs to expected outputs or state changes),
  not tests that only execute lines to raise coverage.
- Never loosen thresholds, lint rules, format config, or compiler settings to make a build pass.
  Report the problem instead. Do not edit `.swiftlint.yml`, `.swiftformat`, `.periphery.*`,
  `Makefile`, or `.github/workflows/` unless the user asked for that change.
- Do not use the Combine framework; use async/await.

## Known gate failures (as of the gates being introduced)

- Strict concurrency (`SWIFT_STRICT_CONCURRENCY=complete`) and warnings-as-errors are not enabled yet.
  The app target is clean, but the test target has about 67 diagnostics because it lacks the app's
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

Do not hide these. Do not make them worse.

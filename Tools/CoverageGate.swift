// Fails if line coverage of the app target is below .quality/coverage-threshold.
// Usage: swift Tools/CoverageGate.swift <path/to/tests.xcresult>
import Foundation

let target = "JblOnMac.app"

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func run(_ executable: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
    } catch {
        fail("error: could not run \(executable): \(error)", code: 2)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("error: \(executable) exited with \(process.terminationStatus)", code: 2)
    }
    return String(decoding: data, as: UTF8.self)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: CoverageGate.swift <xcresult>", code: 64)
}

let result = CommandLine.arguments[1]

let thresholdText = (try? String(contentsOfFile: ".quality/coverage-threshold", encoding: .utf8)) ?? ""
guard let threshold = Int(thresholdText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    fail("error: .quality/coverage-threshold must contain an integer percentage", code: 2)
}

/// Report line: "<id> <name> <files> <pct>% (<covered>/<total>)"
let report = run("/usr/bin/xcrun", ["xccov", "view", "--report", "--only-targets", result])
guard let line = report.split(separator: "\n").first(where: { $0.contains(" \(target) ") }),
      let open = line.lastIndex(of: "("),
      let close = line.lastIndex(of: ")"),
      case let counts = line[line.index(after: open) ..< close].split(separator: "/"),
      counts.count == 2,
      let covered = Int(counts[0]),
      let total = Int(counts[1]),
      total > 0
else {
    fail("error: no coverage found for target \(target)", code: 2)
}

// Hundredths of a percent, truncated, so rounding can never let a failing value through.
let actual = covered * 10000 / total
let percent = String(format: "%d.%02d", actual / 100, actual % 100)
print("Line coverage for \(target): \(percent)% (\(covered)/\(total) lines), required: \(threshold)%")

if actual < threshold * 100 {
    fail("FAIL: coverage is below the \(threshold)% threshold. Add tests; do not lower the threshold.", code: 1)
}

print("OK")

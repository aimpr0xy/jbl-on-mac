/// Short description of an optional error for log lines.
func describe(_ error: (any Error)?) -> String {
    error.map { String(describing: $0) } ?? "nil"
}

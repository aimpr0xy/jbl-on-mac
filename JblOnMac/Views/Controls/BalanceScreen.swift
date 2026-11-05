import SwiftUI

/// Left / right balance slider (-16 ... 16), reached from the Balance row.
struct BalanceScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen
    /// The thumb position while dragging. It moves freely and snaps to a step on release, while the
    /// stored state and the writes use the rounded step.
    @State private var dragValue: Double?

    /// The balance step (-16 ... 16) closest to a slider position.
    static func step(for position: Double) -> Int {
        Int(position.rounded())
    }

    var body: some View {
        let binding = Binding<Double>(
            get: { dragValue ?? Double(headphones.state.balance ?? 0) },
            set: {
                dragValue = $0
                headphones.setBalance(Self.step(for: $0))
            }
        )
        let value = headphones.state.balance ?? 0
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Balance") {
                screen = .controls
            } trailing: {
                Text(value == 0 ? "Center" : "\(value < 0 ? "L" : "R") \(abs(value))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("L").foregroundStyle(.secondary)
                Slider(value: binding, in: -16 ... 16) { editing in
                    if !editing {
                        dragValue = nil
                    }
                }
                Text("R").foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityLabel("Left right balance")
        }
    }
}

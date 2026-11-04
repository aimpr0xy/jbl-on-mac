import SwiftUI

/// Left / right balance slider (-16 ... 16), reached from the Balance row.
struct BalanceScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        let binding = Binding<Double>(
            get: { Double(headphones.state.balance ?? 0) },
            set: { headphones.setBalance(Int($0)) }
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
                Slider(value: binding, in: -16 ... 16, step: 1)
                Text("R").foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityLabel("Left right balance")
        }
    }
}

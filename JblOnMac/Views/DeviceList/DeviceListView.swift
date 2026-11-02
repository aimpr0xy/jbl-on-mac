import SwiftUI

struct DeviceListView: View {
    let headphones: HeadphoneController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "JBL on Mac") {
                EmptyView()
            }

            if headphones.devices.isEmpty {
                Text("Searching for nearby JBL products…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }

            ForEach(headphones.devices) { device in
                DeviceRow(headphones: headphones, device: device)
            }

            if let error = headphones.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
    }
}

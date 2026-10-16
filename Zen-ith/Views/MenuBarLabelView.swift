import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            if viewModel.isScanning {
                Image(systemName: "arrow.triangle.2.circlepath")
            } else if viewModel.isOverAlertThreshold {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                Image(systemName: "sparkles")
            }

            if settings.showSizeInMenuBar {
                if viewModel.isScanning && viewModel.items.isEmpty {
                    Text("スキャン中...")
                } else {
                    Text(ByteFormatter.string(fromBytes: viewModel.totalReclaimableBytes))
                }
            }
        }
    }
}

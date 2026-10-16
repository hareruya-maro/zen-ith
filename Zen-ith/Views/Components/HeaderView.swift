import SwiftUI

struct HeaderView: View {
    @ObservedObject var viewModel: ScannerViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ByteFormatter.string(fromBytes: viewModel.totalReclaimableBytes))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.isOverAlertThreshold ? .orange : .primary)

                    Text("削減可能")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                        Text("開発キャッシュ・不要ファイルを走査中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let lastScan = viewModel.lastScanDate {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("最終スキャン: \(ByteFormatter.relativeDateString(from: lastScan))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                viewModel.startScan()
            } label: {
                Label("再スキャン", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isScanning || viewModel.isCleaning)
            .help("今すぐ再スキャンを実行")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(6)
            .contentShape(Rectangle())
            .help("設定を開く")
            .accessibilityLabel("設定")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

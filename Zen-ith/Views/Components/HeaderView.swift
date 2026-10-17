import SwiftUI

struct HeaderView: View {
    @ObservedObject var viewModel: ScannerViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("最終スキャン: \(ByteFormatter.relativeDateString(from: lastScan, now: context.date))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
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

            if viewModel.diskSpace.totalBytes > 0 {
                diskSpaceGaugeSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var diskSpaceGaugeSection: some View {
        let disk = viewModel.diskSpace
        let selected = viewModel.selectedBytes
        let projectedAvail = disk.projectedAvailableBytes(reclaiming: selected)
        let remainingUsedRatio = disk.remainingUsedFraction(reclaiming: selected)
        let reclaimableRatio = disk.reclaimableFraction(reclaiming: selected)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Mac空き容量: \(ByteFormatter.string(fromBytes: disk.availableBytes)) / \(ByteFormatter.string(fromBytes: disk.totalBytes))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if selected > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("削除後: \(ByteFormatter.string(fromBytes: projectedAvail)) (+\(ByteFormatter.string(fromBytes: selected)))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.green)
                }
            }

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let usedWidth = max(0, totalWidth * remainingUsedRatio)
                let reclaimWidth = selected > 0 ? max(4, totalWidth * reclaimableRatio) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(disk.usedFraction >= 0.85 ? Color.orange.opacity(0.8) : Color.accentColor.opacity(0.75))
                            .frame(width: min(totalWidth, usedWidth))

                        if reclaimWidth > 0 {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: min(max(0, totalWidth - usedWidth), reclaimWidth))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 6)
            .help("青/オレンジ: 残りの使用領域 • 緑: 選択中の削減予定領域 (\(ByteFormatter.string(fromBytes: selected))) • グレー: 空き領域")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}


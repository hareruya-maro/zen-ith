import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings

    private var appIcon: NSImage? {
        NSImage(named: NSImage.applicationIconName) ?? NSApplication.shared.applicationIconImage
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                // アプリアイコン
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                }

                // 容量アラート設定値以上の場合は警告バッジを表示
                if viewModel.isOverAlertThreshold {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7.5, height: 7.5)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.85), lineWidth: 1)
                        )
                        .offset(x: 2, y: -2)
                } else if viewModel.isScanning {
                    // スキャン中は進行中インジケータを小さく表示
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5.5, height: 5.5)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 0.8)
                        )
                        .offset(x: 1.5, y: -1.5)
                }
            }
            .frame(width: 20, height: 18)

            // オプション：容量テキストの併記が有効な場合のみ表示
            if settings.showSizeInMenuBar {
                if viewModel.isScanning && viewModel.items.isEmpty {
                    Text("スキャン中...")
                        .font(.system(size: 11.5))
                } else {
                    Text(ByteFormatter.string(fromBytes: viewModel.totalReclaimableBytes))
                        .font(.system(size: 11.5, design: .rounded))
                }
            }
        }
    }
}

import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                // アプリアイコンの3層を単色化。色はメニューバーの外観に追従する。
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Zen-ith")

                // 容量アラート設定値以上の場合は警告バッジを表示
                if viewModel.isOverAlertThreshold {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6.5, height: 6.5)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                        .offset(x: 3, y: -2)
                } else if viewModel.isScanning {
                    // スキャン中は進行中インジケータを小さく表示
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 0.8)
                        )
                        .offset(x: 2.5, y: -1.5)
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

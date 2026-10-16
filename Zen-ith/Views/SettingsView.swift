import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onBack: () -> Void
    let onSettingsChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ナビゲーションヘッダー
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Zen-ith 設定")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                // バランス用のダミースペース
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 削除方式
                    VStack(alignment: .leading, spacing: 8) {
                        Label("削除（クリーンアップ）方式", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))

                        ForEach(DeletionMode.allCases) { mode in
                            Button {
                                settings.deletionMode = mode
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: settings.deletionMode == mode ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(settings.deletionMode == mode ? Color.accentColor : Color.secondary)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text(mode.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(settings.deletionMode == mode ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    // ダウンロード＆ローカル不要ファイル監視対象
                    VStack(alignment: .leading, spacing: 8) {
                        Label("スマート整理の対象フォルダ", systemImage: "folder.badge.gearshape")
                            .font(.system(size: 13, weight: .semibold))

                        Toggle("ダウンロード (~/Downloads)", isOn: $settings.scanDownloadsFolder)
                            .font(.system(size: 12))
                            .onChange(of: settings.scanDownloadsFolder) { _, _ in
                                onSettingsChanged()
                            }

                        Toggle("デスクトップ (~/Desktop)", isOn: $settings.scanDesktopFolder)
                            .font(.system(size: 12))
                            .onChange(of: settings.scanDesktopFolder) { _, _ in
                                onSettingsChanged()
                            }
                    }

                    Divider()

                    // メニューバー・アラート表示
                    VStack(alignment: .leading, spacing: 10) {
                        Label("メニューバー表示・容量アラート", systemImage: "menubar.rectangle")
                            .font(.system(size: 13, weight: .semibold))

                        Toggle("メニューバーに検出容量を表示する", isOn: $settings.showSizeInMenuBar)
                            .font(.system(size: 12))

                        HStack {
                            Text("容量アラート閾値")
                                .font(.system(size: 12))
                            Spacer()
                            Picker("容量アラート閾値", selection: $settings.alertThresholdGB) {
                                Text("OFF").tag(0)
                                Text("30 GB 超過時").tag(30)
                                Text("50 GB 超過時").tag(50)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // フッター：アプリ終了ボタン
            HStack {
                Text("Zen-ith MVP (Phase 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("アプリを終了", systemImage: "power")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

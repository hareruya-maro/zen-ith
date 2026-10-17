import SwiftUI

struct ScanItemRowView: View {
    let item: ScanItem
    let isAIExpanded: Bool
    let isCleaning: Bool
    var hasCleanupFailure: Bool = false
    let onToggle: () -> Void
    let onToggleAI: () -> Void
    let onRevealInFinder: () -> Void
    let onDeleteSingle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name) を選択")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if hasCleanupFailure {
                        Text("⛔ スキップ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15), in: Capsule())
                    }

                    if item.isCaution {
                        Text("⚠️ 要確認")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .help(item.cautionReason ?? "削除前に確認が推奨される項目です")
                    }

                    if let badge = item.smartBadge {
                        Text(badge.displayText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(badgeForegroundColor(for: badge))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(badgeBackgroundColor(for: badge), in: Capsule())
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.subtitle)
                        .font(.system(size: 10.5, design: item.isFileSystemItem ? .monospaced : .default))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if item.isFileSystemItem {
                        let days = item.ageInDays()
                        if days > 0 {
                            Text("• \(days)日前")
                                .font(.system(size: 10))
                                .foregroundStyle(days >= 30 ? .orange : .secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(hoverTooltipText)

            // 容量バッジ（サイズに応じた色分け: 1GB未満グレー、1〜5GBオレンジ、5GB以上赤）
            Text(ByteFormatter.string(fromBytes: item.sizeBytes))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(sizeBadgeTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(sizeBadgeBackgroundColor, in: RoundedRectangle(cornerRadius: 4))

            // ✨ AI解説・質問ボタン
            Button(action: onToggleAI) {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("AI解説")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(isAIExpanded ? Color.white : Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    isAIExpanded ? Color.accentColor : Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 5)
                )
            }
            .buttonStyle(.plain)
            .help("「これは消して良い？」をAI・スマート解析で診断＆質問")

            if item.isFileSystemItem {
                Button(action: onRevealInFinder) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Finderで開く\n\(item.url.path)")
                .accessibilityLabel("\(item.name) をFinderで開く")
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .help("Docker CLI (docker prune) 経由でクリーンアップします")
            }

            // 🗑️ 単一項目削除ボタン
            Button(action: onDeleteSingle) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(isCleaning)
            .help("この項目のみをすぐに削除 (\(ByteFormatter.string(fromBytes: item.sizeBytes)))")
            .accessibilityLabel("\(item.name) を削除")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var hoverTooltipText: String {
        if item.isFileSystemItem {
            return "\(item.name)\nフルパス: \(item.url.path)"
        }
        return "\(item.name)\n\(item.subtitle)"
    }

    private var sizeBadgeTextColor: Color {
        switch item.sizeSeverity {
        case .normal: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    private var sizeBadgeBackgroundColor: Color {
        switch item.sizeSeverity {
        case .normal: Color.secondary.opacity(0.12)
        case .warning: Color.orange.opacity(0.16)
        case .critical: Color.red.opacity(0.16)
        }
    }

    private func badgeForegroundColor(for badge: SmartBadge) -> Color {
        switch badge {
        case .installedApp: .green
        case .extractedArchive: .blue
        case .exactDuplicate: .purple
        case .workspaceArtifact: .indigo
        case .dockerReclaimable: .cyan
        case .oldInstaller, .oldArchive: .secondary
        }
    }

    private func badgeBackgroundColor(for badge: SmartBadge) -> Color {
        switch badge {
        case .installedApp: Color.green.opacity(0.15)
        case .extractedArchive: Color.blue.opacity(0.15)
        case .exactDuplicate: Color.purple.opacity(0.15)
        case .workspaceArtifact: Color.indigo.opacity(0.15)
        case .dockerReclaimable: Color.cyan.opacity(0.15)
        case .oldInstaller, .oldArchive: Color.secondary.opacity(0.14)
        }
    }
}

import SwiftUI

struct ScanItemRowView: View {
    let item: ScanItem
    let onToggle: () -> Void
    let onRevealInFinder: () -> Void

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

                HStack(spacing: 6) {
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    let days = item.ageInDays()
                    if days > 0 {
                        Text("• \(days)日前")
                            .font(.system(size: 10))
                            .foregroundStyle(days >= 30 ? .orange : .secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            // 容量バッジ（サイズに応じた色分け: 1GB未満グレー、1〜5GBオレンジ、5GB以上赤）
            Text(ByteFormatter.string(fromBytes: item.sizeBytes))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(sizeBadgeTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(sizeBadgeBackgroundColor, in: RoundedRectangle(cornerRadius: 4))

            Button(action: onRevealInFinder) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Finderで開く")
            .accessibilityLabel("\(item.name) をFinderで開く")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
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
        case .oldInstaller, .oldArchive: .secondary
        }
    }

    private func badgeBackgroundColor(for badge: SmartBadge) -> Color {
        switch badge {
        case .installedApp: Color.green.opacity(0.15)
        case .extractedArchive: Color.blue.opacity(0.15)
        case .exactDuplicate: Color.purple.opacity(0.15)
        case .oldInstaller, .oldArchive: Color.secondary.opacity(0.14)
        }
    }
}

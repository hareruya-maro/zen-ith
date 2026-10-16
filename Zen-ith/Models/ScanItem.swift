import Foundation

/// 個別スキャンアイテムに付与するスマート判定バッジ
enum SmartBadge: Hashable, Sendable {
    case installedApp(appName: String)
    case extractedArchive(folderName: String)
    case exactDuplicate(originalFileName: String)
    case oldInstaller
    case oldArchive

    var displayText: String {
        switch self {
        case .installedApp:
            "✅ インストール済"
        case .extractedArchive:
            "📂 解凍済"
        case .exactDuplicate(let originalFileName):
            "👯 重複: \(originalFileName)"
        case .oldInstaller:
            "📦 古いインストーラー"
        case .oldArchive:
            "🗜️ 古いアーカイブ"
        }
    }

    /// 経過日数に関わらず「✨推奨」で即座に削除推奨とする確定バッジかどうか
    var isImmediateRecommendation: Bool {
        switch self {
        case .installedApp, .extractedArchive, .exactDuplicate:
            true
        case .oldInstaller, .oldArchive:
            false
        }
    }
}

/// 容量に応じた視覚化レベル（バッジ色分け用）
enum SizeSeverity: Sendable {
    case normal      // 1GB未満: グレー
    case warning     // 1GB〜5GB: オレンジ
    case critical    // 5GB以上: 赤

    static func from(bytes: Int64) -> SizeSeverity {
        let oneGB: Int64 = 1_000_000_000
        let fiveGB: Int64 = 5_000_000_000
        if bytes >= fiveGB {
            return .critical
        } else if bytes >= oneGB {
            return .warning
        } else {
            return .normal
        }
    }
}

/// スキャンされた個別アイテム
struct ScanItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let url: URL
    let sizeBytes: Int64
    let lastModified: Date
    let category: ScanCategoryType
    let smartBadge: SmartBadge?
    let isCaution: Bool
    let cautionReason: String?
    var isSelected: Bool

    init(
        id: String? = nil,
        name: String,
        subtitle: String,
        url: URL,
        sizeBytes: Int64,
        lastModified: Date,
        category: ScanCategoryType,
        smartBadge: SmartBadge? = nil,
        isCaution: Bool = false,
        cautionReason: String? = nil,
        isSelected: Bool = false
    ) {
        self.id = id ?? url.path
        self.name = name
        self.subtitle = subtitle
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.category = category
        self.smartBadge = smartBadge
        self.isCaution = isCaution
        self.cautionReason = cautionReason
        self.isSelected = isSelected
    }

    /// 現在からの経過日数
    func ageInDays(now: Date = Date()) -> Int {
        let interval = now.timeIntervalSince(lastModified)
        return max(0, Int(interval / 86_400))
    }

    var sizeSeverity: SizeSeverity {
        SizeSeverity.from(bytes: sizeBytes)
    }

    /// 指定されたスマートフィルタプリセットにおいて選択状態にすべきかを判定する
    func matchesFilter(_ preset: SmartFilterPreset, now: Date = Date()) -> Bool {
        // ArchivesやOllamaモデルなどの要注意項目は自動一括選択から常に除外（個別選択のみ許可）
        if isCaution {
            return false
        }

        let days = ageInDays(now: now)

        switch preset {
        case .recommended:
            // 確定バッジ（インストール済DMG、解凍済ZIP、完全重複ファイル）は経過日数に関わらず推奨ON
            if let badge = smartBadge, badge.isImmediateRecommendation {
                return true
            }
            // それ以外は30日以上放置されたものを選択
            return days >= 30

        case .all:
            return true

        case .olderThan30Days:
            return days >= 30

        case .olderThan90Days:
            return days >= 90
        }
    }
}

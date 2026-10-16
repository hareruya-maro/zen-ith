import Foundation

/// スマートフィルタ（一括選択プリセット）
enum SmartFilterPreset: String, CaseIterable, Identifiable, Sendable {
    case recommended = "recommended"
    case all = "all"
    case olderThan30Days = "olderThan30Days"
    case olderThan90Days = "olderThan90Days"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: "✨推奨"
        case .all: "すべて"
        case .olderThan30Days: "> 30日"
        case .olderThan90Days: "> 90日"
        }
    }
}

/// 削除（クリーンアップ）方式
enum DeletionMode: String, CaseIterable, Identifiable, Sendable {
    case hybrid = "hybrid"
    case trashOnly = "trashOnly"
    case permanentOnly = "permanentOnly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hybrid: "ハイブリッド（推奨）"
        case .trashOnly: "すべてゴミ箱へ移動"
        case .permanentOnly: "すべて完全に削除"
        }
    }

    var subtitle: String {
        switch self {
        case .hybrid: "開発キャッシュは即座に完全削除し、ダウンロードファイルは安全のためゴミ箱へ移動します"
        case .trashOnly: "すべての項目をFinderのゴミ箱へ移動します（後から戻すことが可能）"
        case .permanentOnly: "すべての項目をゴミ箱を経由せず即座に完全消去します（空き容量がすぐ回復）"
        }
    }

    func shouldMoveToTrash(for category: ScanCategoryType) -> Bool {
        switch self {
        case .hybrid:
            return category.isUserDownloadCategory
        case .trashOnly:
            return true
        case .permanentOnly:
            return false
        }
    }
}

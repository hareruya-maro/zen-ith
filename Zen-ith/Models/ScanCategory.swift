import Foundation

/// スキャン結果の大分類カテゴリ
enum ScanCategoryType: String, CaseIterable, Identifiable, Sendable {
    case downloads = "downloads"
    case xcode = "xcode"
    case android = "android"
    case nodeWeb = "nodeWeb"
    case pythonAI = "pythonAI"
    case cloudOther = "cloudOther"
    case ideEditor = "ideEditor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "ダウンロード整理"
        case .xcode: "Xcode / iOS"
        case .android: "Android"
        case .nodeWeb: "Node.js / Web"
        case .pythonAI: "Python / AI"
        case .cloudOther: "クラウド / 開発ツール"
        case .ideEditor: "IDE / エディタ"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: "tray.and.arrow.down.fill"
        case .xcode: "hammer.fill"
        case .android: "cpu.fill"
        case .nodeWeb: "globe"
        case .pythonAI: "brain.head.profile"
        case .cloudOther: "cloud.fill"
        case .ideEditor: "curlybraces.square.fill"
        }
    }

    /// ダウンロード等のユーザーファイルか、開発キャッシュか（ハイブリッド削除の判定に使用）
    var isUserDownloadCategory: Bool {
        self == .downloads
    }
}

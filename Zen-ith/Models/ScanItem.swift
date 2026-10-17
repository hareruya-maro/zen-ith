import Foundation

/// Dockerのクリーンアップ対象リソース種別
enum DockerResourceType: String, CaseIterable, Hashable, Sendable {
    case images = "Images"
    case containers = "Containers"
    case localVolumes = "Local Volumes"
    case buildCache = "Build Cache"

    var displayName: String {
        switch self {
        case .images: "Docker Images (未使用イメージ)"
        case .containers: "Docker Containers (停止中コンテナ)"
        case .localVolumes: "Docker Local Volumes (永続化ボリューム)"
        case .buildCache: "Docker Build Cache (BuildKitキャッシュ)"
        }
    }

    var isCaution: Bool {
        self == .localVolumes
    }

    var cautionReason: String? {
        if self == .localVolumes {
            return "ローカルDB等の永続化データが消える可能性があるため、一括選択から除外されています（個別選択のみ可能）"
        }
        return nil
    }

    /// スマートフィルタに応じた docker prune サブコマンド引数を生成する
    func pruneArguments(for preset: SmartFilterPreset) -> [String] {
        let filterHourArg: [String] = switch preset {
        case .recommended, .olderThan30Days:
            ["--filter", "until=720h"]
        case .olderThan90Days:
            ["--filter", "until=2160h"]
        case .all:
            []
        }

        switch self {
        case .images:
            return ["image", "prune", "-a"] + filterHourArg + ["-f"]
        case .containers:
            return ["container", "prune"] + filterHourArg + ["-f"]
        case .buildCache:
            return ["builder", "prune"] + filterHourArg + ["-f"]
        case .localVolumes:
            // docker volume prune は until フィルタ非対応のため -f のみ
            return ["volume", "prune", "-f"]
        }
    }
}

/// Docker仮想ディスクファイル情報（Docker.raw / OrbStack 等）
struct DockerDiskInfo: Identifiable, Hashable, Sendable {
    var id: String { diskURL.path }
    let providerName: String
    let diskURL: URL
    let allocatedBytes: Int64
    let hintText: String
}

/// 個別スキャンアイテムに付与するスマート判定バッジ
enum SmartBadge: Hashable, Sendable {
    case installedApp(appName: String)
    case extractedArchive(folderName: String)
    case exactDuplicate(originalFileName: String)
    case oldInstaller
    case oldArchive
    case workspaceArtifact(kindLabel: String)
    case dockerReclaimable(totalSizeLabel: String)

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
        case .workspaceArtifact(let kindLabel):
            "📁 \(kindLabel)"
        case .dockerReclaimable(let totalSizeLabel):
            "🐳 総容量 \(totalSizeLabel)"
        }
    }

    /// 経過日数に関わらず「✨推奨」で即座に削除推奨とする確定バッジかどうか
    var isImmediateRecommendation: Bool {
        switch self {
        case .installedApp, .extractedArchive, .exactDuplicate:
            true
        case .oldInstaller, .oldArchive, .workspaceArtifact, .dockerReclaimable:
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

/// スキャンされた個別アイテムのアクション種別
enum ScanItemTargetKind: Hashable, Sendable {
    case fileSystem
    case dockerPrune(DockerResourceType)
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
    let targetKind: ScanItemTargetKind
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
        targetKind: ScanItemTargetKind = .fileSystem,
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
        self.targetKind = targetKind
        self.smartBadge = smartBadge
        self.isCaution = isCaution
        self.cautionReason = cautionReason
        self.isSelected = isSelected
    }

    var isFileSystemItem: Bool {
        if case .fileSystem = targetKind {
            return true
        }
        return false
    }

    /// 現在からの経過日数
    func ageInDays(now: Date = Date()) -> Int {
        guard isFileSystemItem else { return 0 }
        let interval = now.timeIntervalSince(lastModified)
        return max(0, Int(interval / 86_400))
    }

    var sizeSeverity: SizeSeverity {
        SizeSeverity.from(bytes: sizeBytes)
    }

    /// 指定されたスマートフィルタプリセットにおいて選択状態にすべきかを判定する
    func matchesFilter(_ preset: SmartFilterPreset, now: Date = Date()) -> Bool {
        // ArchivesやOllamaモデル、Docker Local Volumesなどの要注意項目は自動一括選択から常に除外
        if isCaution {
            return false
        }

        // Docker項目（Local Volumes以外）はプリセットの日数自体が `docker prune --filter until=XXh` にマッピングされるため選択ON
        if case .dockerPrune = targetKind {
            return sizeBytes > 0
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

    /// 検索キーワード（スペース区切りAND検索）に一致するか判定する
    func matchesSearchQuery(_ rawQuery: String) -> Bool {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let tokens = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return true }

        let badgeText = smartBadge?.displayText ?? ""
        let searchableFields = [
            name,
            subtitle,
            url.path,
            category.title,
            badgeText
        ]

        return tokens.allSatisfy { token in
            searchableFields.contains { field in
                field.localizedStandardContains(token)
            }
        }
    }
}


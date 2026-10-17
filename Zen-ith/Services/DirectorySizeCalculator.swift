import Foundation

nonisolated struct DirectoryMetrics: Sendable {
    let sizeBytes: Int64
    let lastModified: Date
}

nonisolated enum DirectorySizeCalculator {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .addedToDirectoryDateKey,
        .creationDateKey
    ]

    /// 指定されたURL（ファイルまたはディレクトリ）のサイズと最終更新日時を計算する
    static func calculateMetrics(for url: URL, preferAddedDate: Bool = false) -> DirectoryMetrics? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        guard let rootValues = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }

        // シンボリックリンクは走査対象外
        if rootValues.isSymbolicLink == true {
            return nil
        }

        let rootDate: Date = if preferAddedDate {
            rootValues.addedToDirectoryDate ?? rootValues.creationDate ?? rootValues.contentModificationDate ?? .distantPast
        } else {
            rootValues.contentModificationDate ?? rootValues.creationDate ?? .distantPast
        }

        // 単一ファイルの場合
        if rootValues.isRegularFile == true {
            let size = Int64(
                rootValues.totalFileAllocatedSize
                ?? rootValues.fileAllocatedSize
                ?? rootValues.fileSize
                ?? 0
            )
            return size > 0 ? DirectoryMetrics(sizeBytes: size, lastModified: rootDate) : nil
        }

        // ディレクトリの場合
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else {
            return nil
        }

        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            if Task.isCancelled { return nil }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values.isRegularFile == true {
                let fileSize = Int64(
                    values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
                )
                totalBytes += fileSize
            }
        }

        guard totalBytes > 0 else { return nil }
        return DirectoryMetrics(sizeBytes: totalBytes, lastModified: rootDate)
    }

    /// 単一ファイルの正確な論理バイトサイズ（fileSizeKey）を取得する（重複ファイル判定用）
    static func exactLogicalFileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    /// Mac本体のボリューム容量（総容量・利用可能空き容量）を取得する
    static func currentDiskSpaceMetrics(for url: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskSpaceMetrics {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return DiskSpaceMetrics(totalBytes: 0, availableBytes: 0)
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available: Int64
        if let importantAvail = values.volumeAvailableCapacityForImportantUsage, importantAvail > 0 {
            available = Int64(importantAvail)
        } else {
            available = Int64(values.volumeAvailableCapacity ?? 0)
        }
        return DiskSpaceMetrics(totalBytes: max(0, total), availableBytes: max(0, min(total, available)))
    }
}

nonisolated struct DiskSpaceMetrics: Sendable, Equatable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }

    /// 選択されたキャッシュを削除した場合の予測空き容量
    func projectedAvailableBytes(reclaiming bytesToReclaim: Int64) -> Int64 {
        let reclaimed = max(0, bytesToReclaim)
        guard totalBytes > 0 else { return availableBytes + reclaimed }
        return min(totalBytes, availableBytes + reclaimed)
    }

    /// クリーンアップ後に残る使用量比率（0.0〜1.0）
    func remainingUsedFraction(reclaiming bytesToReclaim: Int64) -> Double {
        guard totalBytes > 0 else { return 0 }
        let reclaimed = max(0, min(usedBytes, bytesToReclaim))
        return Double(usedBytes - reclaimed) / Double(totalBytes)
    }

    /// 選択された削減分のディスク比率（0.0〜1.0）
    func reclaimableFraction(reclaiming bytesToReclaim: Int64) -> Double {
        guard totalBytes > 0 else { return 0 }
        let reclaimed = max(0, min(usedBytes, bytesToReclaim))
        return Double(reclaimed) / Double(totalBytes)
    }
}


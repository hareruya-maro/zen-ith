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
}

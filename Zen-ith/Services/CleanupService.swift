import Foundation

nonisolated struct CleanupSummary: Sendable {
    let deletedItemIDs: Set<String>
    let freedBytes: Int64
    let failedItems: [(name: String, reason: String)]
}

nonisolated enum CleanupService {
    @concurrent
    static func performCleanup(
        items: [ScanItem],
        deletionMode: DeletionMode,
        activePreset: SmartFilterPreset = .recommended,
        onProgress: @Sendable (Int, Int, String) async -> Void
    ) async -> CleanupSummary {
        let fm = FileManager.default
        let totalCount = items.count
        var deletedIDs: Set<String> = []
        var freedBytes: Int64 = 0
        var failures: [(name: String, reason: String)] = []

        // 削除対象に .dmg が含まれている場合はマウント中イメージ一覧を事前取得
        let mountedDmgMap = items.contains(where: { $0.isFileSystemItem && $0.url.pathExtension.lowercased() == "dmg" })
            ? fetchMountedDiskImages()
            : [:]

        for (index, item) in items.enumerated() {
            await onProgress(index + 1, totalCount, item.name)

            // Docker CLI Prune ターゲットの場合
            if case .dockerPrune(let resourceType) = item.targetKind {
                switch DockerScanner.executeDockerPrune(resourceType: resourceType, preset: activePreset) {
                case .success:
                    deletedIDs.insert(item.id)
                    freedBytes += item.sizeBytes
                case .failure(let error):
                    failures.append((name: item.name, reason: error.localizedDescription))
                }
                continue
            }

            let targetURL = item.url
            guard fm.fileExists(atPath: targetURL.path) else {
                deletedIDs.insert(item.id)
                continue
            }

            // .dmg がマウント中の場合は事前にアンマウント（hdiutil detach）
            if targetURL.pathExtension.lowercased() == "dmg" {
                let standardizedPath = targetURL.standardizedFileURL.path
                if let mountTargets = mountedDmgMap[standardizedPath] {
                    for mountTarget in mountTargets {
                        detachDiskImage(mountTarget: mountTarget)
                    }
                }
            }

            let moveToTrash = deletionMode.shouldMoveToTrash(for: item.category)
            do {
                if moveToTrash {
                    try fm.trashItem(at: targetURL, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: targetURL)
                }
                deletedIDs.insert(item.id)
                freedBytes += item.sizeBytes
            } catch {
                // 万が一 trashItem が失敗した場合（ボリューム外や一時領域等）、キャッシュカテゴリなら removeItem を試みる
                if moveToTrash && !item.category.isUserDownloadCategory {
                    do {
                        try fm.removeItem(at: targetURL)
                        deletedIDs.insert(item.id)
                        freedBytes += item.sizeBytes
                        continue
                    } catch {
                        failures.append((name: item.name, reason: error.localizedDescription))
                    }
                } else {
                    failures.append((name: item.name, reason: error.localizedDescription))
                }
            }
        }

        return CleanupSummary(
            deletedItemIDs: deletedIDs,
            freedBytes: freedBytes,
            failedItems: failures
        )
    }

    /// `/usr/bin/hdiutil info -plist` から現在マウント中の .dmg パスとマウントポイント/デバイス名の対応表を取得する
    private static func fetchMountedDiskImages() -> [String: [String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let images = plist["images"] as? [[String: Any]] else {
                return [:]
            }

            var mapping: [String: [String]] = [:]
            for image in images {
                guard let imagePath = image["image-path"] as? String else { continue }
                let standardizedImagePath = URL(fileURLWithPath: imagePath).standardizedFileURL.path

                var targets: [String] = []
                if let entities = image["system-entities"] as? [[String: Any]] {
                    for entity in entities {
                        if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                            targets.append(mountPoint)
                        } else if let devEntry = entity["dev-entry"] as? String, !devEntry.isEmpty {
                            targets.append(devEntry)
                        }
                    }
                }
                if !targets.isEmpty {
                    mapping[standardizedImagePath, default: []].append(contentsOf: targets)
                }
            }
            return mapping
        } catch {
            return [:]
        }
    }

    private static func detachDiskImage(mountTarget: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountTarget, "-force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // アンマウント失敗時はそのまま削除処理へ進む
        }
    }
}

import AppKit
import Foundation

nonisolated struct CleanupFailureDetail: Identifiable, Hashable, Sendable {
    var id: String { itemID }
    let itemID: String
    let itemName: String
    let url: URL
    let category: ScanCategoryType
    let rawErrorMessage: String
    let reasonTitle: String
    let remediationSteps: [String]
    let suggestedTerminalCommand: String?
    let canRetryWithAdmin: Bool
    let needsFullDiskAccessHint: Bool
}

nonisolated struct CleanupSummary: Sendable {
    let deletedItemIDs: Set<String>
    let freedBytes: Int64
    let failedItems: [CleanupFailureDetail]
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
        var failures: [CleanupFailureDetail] = []

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
                    let args = (["docker"] + resourceType.pruneArguments(for: activePreset)).joined(separator: " ")
                    failures.append(
                        CleanupFailureDetail(
                            itemID: item.id,
                            itemName: item.name,
                            url: item.url,
                            category: item.category,
                            rawErrorMessage: error.localizedDescription,
                            reasonTitle: "Docker コマンドの実行に失敗しました",
                            remediationSteps: [
                                "Docker Desktop または OrbStack が起動しているか確認してください。",
                                "使用中のリソースが含まれている場合はコンテナを停止してから再試行してください。"
                            ],
                            suggestedTerminalCommand: args,
                            canRetryWithAdmin: false,
                            needsFullDiskAccessHint: false
                        )
                    )
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
            } catch let initialError {
                // 1. ゴミ箱移動が失敗した場合、キャッシュカテゴリなら直接削除を試みる
                if moveToTrash && !item.category.isUserDownloadCategory {
                    if (try? fm.removeItem(at: targetURL)) != nil {
                        deletedIDs.insert(item.id)
                        freedBytes += item.sizeBytes
                        continue
                    }
                }

                // 2. Simulator Device の場合は `xcrun simctl delete <UDID>` での正規削除を試みる
                if targetURL.path.contains("/CoreSimulator/Devices/") {
                    let udid = targetURL.lastPathComponent
                    if tryDeleteSimulatorWithSimctl(udid: udid), !fm.fileExists(atPath: targetURL.path) {
                        deletedIDs.insert(item.id)
                        freedBytes += item.sizeBytes
                        continue
                    }
                }

                // 3. 読み取り専用属性（Go module cache 等）が原因の場合は chmod -R u+w 後に再試行
                if tryMakeWritableAndRemove(url: targetURL, moveToTrash: moveToTrash && item.category.isUserDownloadCategory) {
                    deletedIDs.insert(item.id)
                    freedBytes += item.sizeBytes
                    continue
                }

                // 4. それでも削除できなかった場合は詳細な原因診断と対処法を生成
                let detail = diagnoseFailure(
                    for: item,
                    error: initialError,
                    deletionMode: deletionMode
                )
                failures.append(detail)
            }
        }

        return CleanupSummary(
            deletedItemIDs: deletedIDs,
            freedBytes: freedBytes,
            failedItems: failures
        )
    }

    /// macOS 標準の管理者認証ダイアログ（Touch ID / パスワード）を使って root 所有ファイル等を強制削除する
    @concurrent
    static func performAdminCleanup(failures: [CleanupFailureDetail], itemsByID: [String: ScanItem]) async -> CleanupSummary {
        let targets = failures.filter(\.canRetryWithAdmin)
        guard !targets.isEmpty else {
            return CleanupSummary(deletedItemIDs: [], freedBytes: 0, failedItems: failures)
        }

        // シェル安全なシングルクォートエスケープで rm -rf コマンドを組み立てる
        let escapedPaths = targets.map { detail -> String in
            let p = detail.url.path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(p)'"
        }.joined(separator: " ")

        let shellCommand = "/bin/rm -rf \(escapedPaths)"
        let appleScriptSource = "do shell script \(appleScriptStringLiteral(shellCommand)) with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptSource]
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let fm = FileManager.default
            var deletedIDs: Set<String> = []
            var freedBytes: Int64 = 0
            var remainingFailures: [CleanupFailureDetail] = []

            for detail in failures {
                if !fm.fileExists(atPath: detail.url.path) {
                    deletedIDs.insert(detail.itemID)
                    freedBytes += itemsByID[detail.itemID]?.sizeBytes ?? 0
                } else {
                    let stderrStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if stderrStr.contains("-128") || stderrStr.localizedStandardContains("User canceled") {
                        remainingFailures.append(detail)
                    } else {
                        remainingFailures.append(
                            CleanupFailureDetail(
                                itemID: detail.itemID,
                                itemName: detail.itemName,
                                url: detail.url,
                                category: detail.category,
                                rawErrorMessage: stderrStr.isEmpty ? detail.rawErrorMessage : stderrStr,
                                reasonTitle: detail.reasonTitle,
                                remediationSteps: detail.remediationSteps + [
                                    "管理者権限でも削除できない場合は「システム設定 > プライバシーとセキュリティ > フルディスクアクセス」で Zen-ith（またはターミナル）を許可してください。"
                                ],
                                suggestedTerminalCommand: detail.suggestedTerminalCommand,
                                canRetryWithAdmin: detail.canRetryWithAdmin,
                                needsFullDiskAccessHint: true
                            )
                        )
                    }
                }
            }

            return CleanupSummary(
                deletedItemIDs: deletedIDs,
                freedBytes: freedBytes,
                failedItems: remainingFailures
            )
        } catch {
            return CleanupSummary(deletedItemIDs: [], freedBytes: 0, failedItems: failures)
        }
    }

    // MARK: - 原因診断ロジック

    static func diagnoseFailure(
        for item: ScanItem,
        error: Error,
        deletionMode: DeletionMode
    ) -> CleanupFailureDetail {
        let nsError = error as NSError
        let path = item.url.path
        let lowerPath = path.lowercased()
        let quotedPath = shellQuote(path)

        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let ownerName = (attrs?[.ownerAccountName] as? String) ?? ""
        let isImmutable = (attrs?[.immutable] as? Bool) ?? false

        let underlyingPOSIX = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
        let posixCode = underlyingPOSIX?.domain == NSPOSIXErrorDomain ? underlyingPOSIX?.code : nil
        let isPermissionError = nsError.code == NSFileWriteNoPermissionError
            || nsError.code == NSFileReadNoPermissionError
            || posixCode == Int(EACCES)
            || posixCode == Int(EPERM)
        let isBusyError = posixCode == Int(EBUSY)
            || nsError.localizedDescription.localizedStandardContains("busy")

        // 1. CoreSimulator dyld 共有キャッシュ または root 所有ファイル
        if lowerPath.contains("/coresimulator/caches") || ownerName == "root" {
            return CleanupFailureDetail(
                itemID: item.id,
                itemName: item.name,
                url: item.url,
                category: item.category,
                rawErrorMessage: "\(nsError.localizedDescription) (所有者: \(ownerName.isEmpty ? "root/system" : ownerName), Code: \(nsError.code))",
                reasonTitle: "管理者権限（root）で保護されたシステムキャッシュです",
                remediationSteps: [
                    "CoreSimulator 等のサービスが root 権限で生成したファイルのため、通常のユーザー権限では削除できません。",
                    "下の「管理者権限で削除 (Touch ID / パスワード)」ボタンを押すか、Simulator を終了した上でターミナルから sudo コマンドを実行してください。"
                ],
                suggestedTerminalCommand: "sudo rm -rf \(quotedPath)",
                canRetryWithAdmin: true,
                needsFullDiskAccessHint: false
            )
        }

        // 2. Simulator 仮想端末（起動中・ロック中）
        if lowerPath.contains("/coresimulator/devices/") {
            let udid = item.url.lastPathComponent
            return CleanupFailureDetail(
                itemID: item.id,
                itemName: item.name,
                url: item.url,
                category: item.category,
                rawErrorMessage: "\(nsError.localizedDescription) (Code: \(nsError.code))",
                reasonTitle: "シミュレータ端末が起動中、または CoreSimulator にロックされています",
                remediationSteps: [
                    "Simulator.app でこの端末が起動している場合は終了してください。",
                    "その後もう一度削除するか、下の simctl コマンドまたは「管理者権限で削除」を実行してください。"
                ],
                suggestedTerminalCommand: "xcrun simctl shutdown \(udid) 2>/dev/null; xcrun simctl delete \(udid)",
                canRetryWithAdmin: true,
                needsFullDiskAccessHint: false
            )
        }

        // 3. ファイルロック設定（uchg / immutable）
        if isImmutable {
            return CleanupFailureDetail(
                itemID: item.id,
                itemName: item.name,
                url: item.url,
                category: item.category,
                rawErrorMessage: nsError.localizedDescription,
                reasonTitle: "ファイルに「ロック（変更不可フラグ）」が設定されています",
                remediationSteps: [
                    "Finder の「情報を見る」でロックを解除するか、「管理者権限で削除」または以下のコマンドでロックを解除して削除してください。"
                ],
                suggestedTerminalCommand: "chflags -R nouchg \(quotedPath) && rm -rf \(quotedPath)",
                canRetryWithAdmin: true,
                needsFullDiskAccessHint: false
            )
        }

        // 4. 別プロセスが使用中（EBUSY / マウント中・起動中アプリ）
        if isBusyError {
            return CleanupFailureDetail(
                itemID: item.id,
                itemName: item.name,
                url: item.url,
                category: item.category,
                rawErrorMessage: "\(nsError.localizedDescription) (EBUSY)",
                reasonTitle: "現在起動中のアプリケーションがこのファイルを使用中です",
                remediationSteps: [
                    "Xcode・Android Studio・ブラウザ・インストーラーなど、このファイルを開いているアプリを終了してから再試行してください。"
                ],
                suggestedTerminalCommand: "lsof +D \(quotedPath)",
                canRetryWithAdmin: true,
                needsFullDiskAccessHint: false
            )
        }

        // 5. アクセス権限エラー（macOS フルディスクアクセス / TCC 保護 または root サブファイル）
        if isPermissionError {
            return CleanupFailureDetail(
                itemID: item.id,
                itemName: item.name,
                url: item.url,
                category: item.category,
                rawErrorMessage: "\(nsError.localizedDescription) (Code: \(nsError.code))",
                reasonTitle: "書き込み・削除権限がないファイルが含まれています",
                remediationSteps: [
                    "フォルダ内に管理者（root）所有のファイルが含まれている場合は「管理者権限で削除」で削除できます。",
                    "macOS のプライバシー保護（TCC）でブロックされている場合は「フルディスクアクセス設定を開く」から Zen-ith を許可してください。"
                ],
                suggestedTerminalCommand: "sudo rm -rf \(quotedPath)",
                canRetryWithAdmin: true,
                needsFullDiskAccessHint: true
            )
        }

        // 6. ゴミ箱移動特有のエラー（すべてゴミ箱へ移動モード時）
        if deletionMode == .trashOnly {
            return CleanupFailureDetail(
                itemID: item.id,
                itemName: item.name,
                url: item.url,
                category: item.category,
                rawErrorMessage: "\(nsError.localizedDescription) (Code: \(nsError.code))",
                reasonTitle: "この項目を「ゴミ箱」へ移動できませんでした",
                remediationSteps: [
                    "一時領域や大容量特殊フォルダはゴミ箱への移動が制限されることがあります。",
                    "設定から削除方式を「ハイブリッド（推奨）」に変更するか、「管理者権限で削除」を実行してください。"
                ],
                suggestedTerminalCommand: "rm -rf \(quotedPath)",
                canRetryWithAdmin: true,
                needsFullDiskAccessHint: false
            )
        }

        // 7. その他のエラー
        return CleanupFailureDetail(
            itemID: item.id,
            itemName: item.name,
            url: item.url,
            category: item.category,
            rawErrorMessage: "\(nsError.localizedDescription) (\(nsError.domain) Code: \(nsError.code))",
            reasonTitle: "システムの保護またはロックにより削除できませんでした",
            remediationSteps: [
                "関連する開発ツール（Xcode / IDE等）を閉じてから再試行するか、「管理者権限で削除」またはターミナルでの手動削除をお試しください。"
            ],
            suggestedTerminalCommand: "sudo rm -rf \(quotedPath)",
            canRetryWithAdmin: true,
            needsFullDiskAccessHint: false
        )
    }

    // MARK: - 自動リカバリ補助メソッド

    private static func tryDeleteSimulatorWithSimctl(udid: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "delete", udid]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func tryMakeWritableAndRemove(url: URL, moveToTrash: Bool) -> Bool {
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "u+w", url.path]
        chmod.standardOutput = FileHandle.nullDevice
        chmod.standardError = FileHandle.nullDevice
        try? chmod.run()
        chmod.waitUntilExit()

        let fm = FileManager.default
        do {
            if moveToTrash {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } else {
                try fm.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }

    private static func shellQuote(_ path: String) -> String {
        if path.contains(" ") || path.contains("(") || path.contains(")") {
            return "\"\(path.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return path
    }

    private static func appleScriptStringLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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

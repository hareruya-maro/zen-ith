import CryptoKit
import Darwin
import Foundation

nonisolated struct DownloadsSmartScanner: Sendable {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]
    static let archiveExtensions: Set<String> = ["zip", "tgz", "rar", "7z"]
    static let compoundArchiveSuffixes: [String] = [".tar.gz", ".tar.bz2", ".tar.xz"]

    private static let noiseTokens: Set<String> = [
        "darwin", "macos", "mac", "osx", "arm64", "aarch64", "x64", "x86", "x86_64",
        "universal", "intel", "silicon", "apple", "installer", "setup", "release",
        "latest", "stable", "desktop", "client", "app", "pkg", "dmg"
    ]

    @concurrent
    static func scanDirectories(
        _ directories: [URL],
        installedAppNames: [String]? = nil
    ) async -> [ScanItem] {
        let apps = installedAppNames ?? fetchInstalledAppNames()

        return await withTaskGroup(of: [ScanItem].self) { group in
            for directory in directories {
                group.addTask {
                    if Task.isCancelled { return [] }
                    return scanSingleDirectory(directory, installedAppNames: apps)
                }
            }

            var allItems: [ScanItem] = []
            for await items in group {
                allItems.append(contentsOf: items)
            }
            return allItems.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    static func scanSingleDirectory(
        _ directoryURL: URL,
        installedAppNames: [String],
        now: Date = Date()
    ) -> [ScanItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path),
              let contents = try? fm.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: [
                      .isRegularFileKey,
                      .isDirectoryKey,
                      .isSymbolicLinkKey,
                      .fileSizeKey,
                      .totalFileAllocatedSizeKey,
                      .fileAllocatedSizeKey,
                      .addedToDirectoryDateKey,
                      .creationDateKey,
                      .contentModificationDateKey
                  ],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        // 同一ディレクトリ内のファイル名・フォルダ名マップを作成
        var entryByName: [String: URL] = [:]
        var directoryNamesLowercased: [String: String] = [:]

        for url in contents {
            let name = url.lastPathComponent
            entryByName[name] = url

            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
               values.isDirectory == true,
               values.isPackage != true {
                directoryNamesLowercased[name.lowercased()] = name
            }
        }

        let normalizedApps: [(original: String, normalized: String)] = installedAppNames.compactMap { app in
            let norm = normalizeCoreName(app)
            return norm.count >= 2 ? (app, norm) : nil
        }

        var items: [ScanItem] = []

        for fileURL in contents {
            if Task.isCancelled { break }

            let fileName = fileURL.lastPathComponent
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey
            ]),
            values.isSymbolicLink != true else {
                continue
            }

            let isRegularFile = values.isRegularFile == true
            let itemDate = values.addedToDirectoryDate
                ?? values.creationDate
                ?? values.contentModificationDate
                ?? .distantPast
            let ageDays = max(0, Int(now.timeIntervalSince(itemDate) / 86_400))

            // 1. 重複ダウンロードファイル判定（3段階チェック: 正規表現 -> バイトサイズ完全一致 -> SHA-256一致）
            if isRegularFile,
               let baseFileName = extractDuplicateBaseFileName(from: fileName),
               let originalURL = entryByName[baseFileName],
               originalURL != fileURL {
                if isVerifiedExactDuplicate(candidateURL: fileURL, originalURL: originalURL) {
                    let sizeBytes = Int64(
                        values.totalFileAllocatedSize
                        ?? values.fileAllocatedSize
                        ?? values.fileSize
                        ?? 0
                    )
                    if sizeBytes > 0 {
                        items.append(
                            ScanItem(
                                name: fileName,
                                subtitle: "\(directoryURL.lastPathComponent) • オリジナルとSHA-256完全一致",
                                url: fileURL,
                                sizeBytes: sizeBytes,
                                lastModified: itemDate,
                                category: .downloads,
                                smartBadge: .exactDuplicate(originalFileName: baseFileName)
                            )
                        )
                        continue
                    }
                }
            }

            // 2. 不要なインストーラー / ディスクイメージ (.dmg, .pkg, .iso, .xip)
            let ext = fileURL.pathExtension.lowercased()
            if installerExtensions.contains(ext) {
                guard let metrics = DirectorySizeCalculator.calculateMetrics(for: fileURL, preferAddedDate: true) else {
                    continue
                }

                if let matchedApp = matchInstalledApp(forInstallerFileName: fileName, installedApps: normalizedApps) {
                    items.append(
                        ScanItem(
                            name: fileName,
                            subtitle: "\(directoryURL.lastPathComponent) • \(matchedApp).app 検出済み",
                            url: fileURL,
                            sizeBytes: metrics.sizeBytes,
                            lastModified: metrics.lastModified,
                            category: .downloads,
                            smartBadge: .installedApp(appName: matchedApp)
                        )
                    )
                } else if ageDays >= 30 {
                    items.append(
                        ScanItem(
                            name: fileName,
                            subtitle: "\(directoryURL.lastPathComponent) • \(ageDays)日前にダウンロード",
                            url: fileURL,
                            sizeBytes: metrics.sizeBytes,
                            lastModified: metrics.lastModified,
                            category: .downloads,
                            smartBadge: .oldInstaller
                        )
                    )
                } else {
                    items.append(
                        ScanItem(
                            name: fileName,
                            subtitle: "\(directoryURL.lastPathComponent) • 未インストール (\(ageDays)日前)",
                            url: fileURL,
                            sizeBytes: metrics.sizeBytes,
                            lastModified: metrics.lastModified,
                            category: .downloads,
                            smartBadge: nil
                        )
                    )
                }
                continue
            }

            // 3. 解凍済みの圧縮アーカイブ (.zip, .tar.gz, .tgz, .rar, .7z)
            if let archiveBaseName = extractArchiveBaseName(from: fileName) {
                guard let metrics = DirectorySizeCalculator.calculateMetrics(for: fileURL, preferAddedDate: true) else {
                    continue
                }

                if let matchedFolder = directoryNamesLowercased[archiveBaseName.lowercased()] {
                    let fromDownload = hasDownloadWhereFromsAttribute(at: fileURL)
                    let originLabel = fromDownload ? "展開済みダウンロードアーカイブ" : "同名フォルダ展開済み"
                    items.append(
                        ScanItem(
                            name: fileName,
                            subtitle: "\(directoryURL.lastPathComponent) • \(originLabel) (\(matchedFolder)/)",
                            url: fileURL,
                            sizeBytes: metrics.sizeBytes,
                            lastModified: metrics.lastModified,
                            category: .downloads,
                            smartBadge: .extractedArchive(folderName: matchedFolder)
                        )
                    )
                } else if ageDays >= 30 {
                    items.append(
                        ScanItem(
                            name: fileName,
                            subtitle: "\(directoryURL.lastPathComponent) • \(ageDays)日経過した圧縮ファイル",
                            url: fileURL,
                            sizeBytes: metrics.sizeBytes,
                            lastModified: metrics.lastModified,
                            category: .downloads,
                            smartBadge: .oldArchive
                        )
                    )
                }
            }
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - 1. インストーラー「インストール済み」スマート判定

    static func fetchInstalledAppNames() -> [String] {
        let fm = FileManager.default
        let appDirs: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var names: Set<String> = []
        for dir in appDirs {
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension.lowercased() == "app" {
                let baseName = url.deletingPathExtension().lastPathComponent
                names.insert(baseName)

                // Info.plist の CFBundleName / CFBundleDisplayName も取得
                let plistURL = url.appendingPathComponent("Contents/Info.plist")
                if let plist = NSDictionary(contentsOf: plistURL) {
                    if let displayName = plist["CFBundleDisplayName"] as? String, !displayName.isEmpty {
                        names.insert(displayName)
                    }
                    if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
                        names.insert(bundleName)
                    }
                }
            }
        }
        return Array(names)
    }

    /// インストーラーのファイル名から記号・バージョン番号・アーキテクチャ文字列を除いたコア名称を抽出する
    static func normalizeCoreName(_ rawName: String) -> String {
        var name = rawName
        // 拡張子が付いていれば除去
        let lower = name.lowercased()
        for ext in installerExtensions {
            if lower.hasSuffix(".\(ext)") {
                name = String(name.dropLast(ext.count + 1))
                break
            }
        }

        // 重複サフィックス (1) などを除去
        name = name.replacingOccurrences(
            of: #"\s*\(\d+\)$"#,
            with: "",
            options: .regularExpression
        )

        // バージョン表記 (例: -4.38.0, _v1.2.3, 2026.1.2 等) を除去
        name = name.replacingOccurrences(
            of: #"(?:[-_.\s]+v?\d+(?:[._]\d+)*(?:[-_][a-zA-Z0-9]+)?)+"#,
            with: " ",
            options: .regularExpression
        )

        // トークン分割してノイズ語（darwin, arm64, universal等）を除去
        let rawTokens = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let filteredTokens = rawTokens.filter { token in
            guard !noiseTokens.contains(token) else { return false }
            // 純粋な数値のみのトークンは除去
            if Int(token) != nil { return false }
            return true
        }

        return filteredTokens.joined()
    }

    static func matchInstalledApp(
        forInstallerFileName fileName: String,
        installedApps: [(original: String, normalized: String)]
    ) -> String? {
        let installerCore = normalizeCoreName(fileName)
        guard installerCore.count >= 3 else { return nil }

        // 完全一致を最優先
        if let exact = installedApps.first(where: { $0.normalized == installerCore }) {
            return exact.original
        }

        // 前方一致または部分一致（4文字以上のコア名同士）
        for app in installedApps where app.normalized.count >= 4 && installerCore.count >= 4 {
            if installerCore.hasPrefix(app.normalized) || app.normalized.hasPrefix(installerCore) {
                return app.original
            }
        }

        return nil
    }

    // MARK: - 2. 解凍済みアーカイブ判定

    static func extractArchiveBaseName(from fileName: String) -> String? {
        let lower = fileName.lowercased()
        for compound in compoundArchiveSuffixes {
            if lower.hasSuffix(compound) {
                let base = String(fileName.dropLast(compound.count))
                return base.isEmpty ? nil : base
            }
        }

        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension.lowercased()
        guard archiveExtensions.contains(ext) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? nil : base
    }

    /// xattr `com.apple.metadata:kMDItemWhereFroms` が付与されているか確認する
    static func hasDownloadWhereFromsAttribute(at url: URL) -> Bool {
        let attrName = "com.apple.metadata:kMDItemWhereFroms"
        let length = getxattr(url.path, attrName, nil, 0, 0, XATTR_NOFOLLOW)
        return length > 0
    }

    // MARK: - 3. 重複ファイル 3段階チェック

    /// Step 1: 正規表現による連番・コピー命名パターンの検知し、オリジナルファイル名を返す
    static func extractDuplicateBaseFileName(from fileName: String) -> String? {
        let nsFileName = fileName as NSString
        let ext = nsFileName.pathExtension
        let stem = ext.isEmpty ? fileName : nsFileName.deletingPathExtension

        // パターン1: `foo (1)`, `foo(2)`
        // パターン2: `foo のコピー`, `foo のコピー 2`, `foo copy`, `foo copy 2`
        // パターン3: `foo 2` (末尾スペース＋1〜2桁の連番)
        let patterns = [
            #"^(.+?)\s*\(\d+\)$"#,
            #"^(.+?)\s*(?:のコピー(?:\s*\d+)?|copy(?:\s*\d+)?)$"#,
            #"^(.+?)\s+([1-9]\d?)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            if let match = regex.firstMatch(in: stem, options: [], range: range),
               let baseRange = Range(match.range(at: 1), in: stem) {
                let baseStem = String(stem[baseRange]).trimmingCharacters(in: .whitespaces)
                guard !baseStem.isEmpty else { continue }
                return ext.isEmpty ? baseStem : "\(baseStem).\(ext)"
            }
        }

        return nil
    }

    /// Step 2 & Step 3: バイトサイズ完全一致と CryptoKit.SHA256 ハッシュ比較
    static func isVerifiedExactDuplicate(candidateURL: URL, originalURL: URL) -> Bool {
        // Step 2: 論理ファイルサイズ（Byte単位）が1バイトの狂いもなく完全一致するか確認
        guard let candidateSize = DirectorySizeCalculator.exactLogicalFileSize(for: candidateURL),
              let originalSize = DirectorySizeCalculator.exactLogicalFileSize(for: originalURL),
              candidateSize > 0,
              candidateSize == originalSize else {
            return false
        }

        // Step 3: SHA-256 ハッシュ比較
        guard let candidateDigest = computeFastFileSHA256(for: candidateURL, fileSize: candidateSize),
              let originalDigest = computeFastFileSHA256(for: originalURL, fileSize: originalSize) else {
            return false
        }

        return candidateDigest == originalDigest
    }

    /// ファイルのSHA-256ハッシュを計算する（64MB以下は全体、64MB超は先頭・中間・末尾各4MBのサンプリングハッシュ）
    static func computeFastFileSHA256(for url: URL, fileSize: Int64) -> SHA256Digest? {
        let fullHashLimit: Int64 = 64 * 1024 * 1024 // 64 MB
        let chunkSize = 4 * 1024 * 1024 // 4 MB

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()

        if fileSize <= fullHashLimit {
            while true {
                if Task.isCancelled { return nil }
                guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else {
                    break
                }
                hasher.update(data: data)
            }
        } else {
            // 先頭・中央・末尾チャンクをハッシュ化
            let offsets: [UInt64] = [
                0,
                UInt64(max(0, (fileSize / 2) - Int64(chunkSize / 2))),
                UInt64(max(0, fileSize - Int64(chunkSize)))
            ]
            for offset in offsets {
                if Task.isCancelled { return nil }
                try? handle.seek(toOffset: offset)
                if let data = try? handle.read(upToCount: chunkSize) {
                    hasher.update(data: data)
                }
            }
        }

        return hasher.finalize()
    }
}

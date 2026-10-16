import Foundation

nonisolated struct CacheScanTarget: Sendable {
    enum Granularity: Sendable {
        case wholeDirectory(displayName: String)
        case subdirectories(labelPrefix: String)
        case archivesTwoLevel(labelPrefix: String)
        case tmpPrefixMatch(directoryURL: URL, prefixes: [String], labelPrefix: String)
    }

    let category: ScanCategoryType
    let baseURL: URL
    let granularity: Granularity
    let isCaution: Bool
    let cautionReason: String?

    init(
        category: ScanCategoryType,
        baseURL: URL,
        granularity: Granularity,
        isCaution: Bool = false,
        cautionReason: String? = nil
    ) {
        self.category = category
        self.baseURL = baseURL
        self.granularity = granularity
        self.isCaution = isCaution
        self.cautionReason = cautionReason
    }
}

nonisolated struct GlobalCacheScanner: Sendable {
    static func defaultTargets(homeDir: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CacheScanTarget] {
        func home(_ relativePath: String) -> URL {
            homeDir.appendingPathComponent(relativePath)
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return [
            // MARK: - Xcode / iOS
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/Xcode/DerivedData"),
                granularity: .subdirectories(labelPrefix: "DerivedData")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/Xcode/Archives"),
                granularity: .archivesTwoLevel(labelPrefix: "Xcode Archive"),
                isCaution: true,
                cautionReason: "リリースビルドのシンボル復元（dSYM）に使用されるアーカイブです"
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/Xcode/iOS DeviceSupport"),
                granularity: .subdirectories(labelPrefix: "iOS DeviceSupport")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/CoreSimulator/Caches"),
                granularity: .subdirectories(labelPrefix: "CoreSimulator Cache")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/CoreSimulator/Devices"),
                granularity: .subdirectories(labelPrefix: "Simulator Device")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Caches/org.swift.swiftpm/repositories"),
                granularity: .subdirectories(labelPrefix: "SwiftPM")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Caches/CocoaPods"),
                granularity: .wholeDirectory(displayName: "CocoaPods Cache")
            ),

            // MARK: - Android
            CacheScanTarget(
                category: .android,
                baseURL: home(".android/avd"),
                granularity: .subdirectories(labelPrefix: "Android AVD"),
                isCaution: true,
                cautionReason: "Androidエミュレータ仮想端末データです"
            ),
            CacheScanTarget(
                category: .android,
                baseURL: home("Library/Android/sdk/system-images"),
                granularity: .subdirectories(labelPrefix: "Android System Image")
            ),
            CacheScanTarget(
                category: .android,
                baseURL: home(".gradle/caches"),
                granularity: .subdirectories(labelPrefix: "Gradle Cache")
            ),
            CacheScanTarget(
                category: .android,
                baseURL: home(".gradle/wrapper/dists"),
                granularity: .subdirectories(labelPrefix: "Gradle Wrapper")
            ),

            // MARK: - Node.js / Web
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home(".npm/_cacache"),
                granularity: .wholeDirectory(displayName: "npm Cache (_cacache)")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home("Library/Caches/Yarn"),
                granularity: .wholeDirectory(displayName: "Yarn Cache")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home("Library/pnpm/store"),
                granularity: .wholeDirectory(displayName: "pnpm Store")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home(".bun/install/cache"),
                granularity: .wholeDirectory(displayName: "Bun Install Cache")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: tmpDir,
                granularity: .tmpPrefixMatch(
                    directoryURL: tmpDir,
                    prefixes: ["metro-", "haste-map-"],
                    labelPrefix: "Metro / React Native Temp"
                )
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home(".expo"),
                granularity: .subdirectories(labelPrefix: "Expo")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home("Library/Caches/ms-playwright"),
                granularity: .subdirectories(labelPrefix: "Playwright Browser")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home("Library/Caches/Cypress"),
                granularity: .subdirectories(labelPrefix: "Cypress Version")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home(".cache/puppeteer"),
                granularity: .subdirectories(labelPrefix: "Puppeteer Browser")
            ),

            // MARK: - Python / AI
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home("Library/Caches/pip"),
                granularity: .wholeDirectory(displayName: "pip Cache")
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home("Library/Caches/pypoetry"),
                granularity: .wholeDirectory(displayName: "Poetry Cache")
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".cache/uv"),
                granularity: .wholeDirectory(displayName: "uv Cache")
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".cache/huggingface/hub"),
                granularity: .subdirectories(labelPrefix: "Hugging Face Hub")
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".cache/torch"),
                granularity: .subdirectories(labelPrefix: "PyTorch Cache")
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".ollama/models"),
                granularity: .wholeDirectory(displayName: "Ollama Local Models"),
                isCaution: true,
                cautionReason: "ローカルLLMの重みデータです（削除すると再pullが必要になります）"
            ),

            // MARK: - クラウド / 開発ツール
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home(".config/gcloud/logs"),
                granularity: .subdirectories(labelPrefix: "gcloud Logs")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home(".aws/cli/cache"),
                granularity: .wholeDirectory(displayName: "AWS CLI Cache")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home(".aws/sam"),
                granularity: .wholeDirectory(displayName: "AWS SAM Cache")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home(".terraform.d/plugin-cache"),
                granularity: .subdirectories(labelPrefix: "Terraform Plugin")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home(".cargo/registry/cache"),
                granularity: .subdirectories(labelPrefix: "Cargo Registry Cache")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home(".cargo/git/db"),
                granularity: .subdirectories(labelPrefix: "Cargo Git DB")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home("go/pkg/mod/cache"),
                granularity: .wholeDirectory(displayName: "Go Module Cache")
            ),
            CacheScanTarget(
                category: .cloudOther,
                baseURL: home("Library/Caches/Homebrew"),
                granularity: .wholeDirectory(displayName: "Homebrew Cache")
            ),

            // MARK: - IDE / エディタ
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Caches/JetBrains"),
                granularity: .subdirectories(labelPrefix: "JetBrains Cache")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Logs/JetBrains"),
                granularity: .subdirectories(labelPrefix: "JetBrains Logs")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Application Support/Code/CachedExtensionVSIXs"),
                granularity: .wholeDirectory(displayName: "VS Code CachedExtensionVSIXs")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Application Support/Code/Cache"),
                granularity: .wholeDirectory(displayName: "VS Code Cache")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Application Support/Code/CachedData"),
                granularity: .wholeDirectory(displayName: "VS Code CachedData")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Application Support/Cursor/CachedExtensionVSIXs"),
                granularity: .wholeDirectory(displayName: "Cursor CachedExtensionVSIXs")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Application Support/Cursor/Cache"),
                granularity: .wholeDirectory(displayName: "Cursor Cache")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Application Support/Cursor/CachedData"),
                granularity: .wholeDirectory(displayName: "Cursor CachedData")
            )
        ]
    }

    @concurrent
    static func scanAll(targets: [CacheScanTarget] = defaultTargets()) async -> [ScanItem] {
        await withTaskGroup(of: [ScanItem].self) { group in
            for target in targets {
                group.addTask {
                    if Task.isCancelled { return [] }
                    return scanTarget(target)
                }
            }

            var results: [ScanItem] = []
            for await items in group {
                results.append(contentsOf: items)
            }
            return results.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    private static func scanTarget(_ target: CacheScanTarget) -> [ScanItem] {
        let fm = FileManager.default

        switch target.granularity {
        case .wholeDirectory(let displayName):
            guard fm.fileExists(atPath: target.baseURL.path),
                  let metrics = DirectorySizeCalculator.calculateMetrics(for: target.baseURL) else {
                return []
            }
            return [
                ScanItem(
                    name: displayName,
                    subtitle: abbreviateHomePath(target.baseURL.path),
                    url: target.baseURL,
                    sizeBytes: metrics.sizeBytes,
                    lastModified: metrics.lastModified,
                    category: target.category,
                    isCaution: target.isCaution,
                    cautionReason: target.cautionReason
                )
            ]

        case .subdirectories(let labelPrefix):
            guard fm.fileExists(atPath: target.baseURL.path),
                  let children = try? fm.contentsOfDirectory(
                      at: target.baseURL,
                      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                      options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            var items: [ScanItem] = []
            for childURL in children {
                if Task.isCancelled { break }
                guard let metrics = DirectorySizeCalculator.calculateMetrics(for: childURL) else {
                    continue
                }
                let friendlyName = formatFriendlyName(for: childURL, labelPrefix: labelPrefix)
                items.append(
                    ScanItem(
                        name: friendlyName,
                        subtitle: "\(labelPrefix) • \(abbreviateHomePath(childURL.path))",
                        url: childURL,
                        sizeBytes: metrics.sizeBytes,
                        lastModified: metrics.lastModified,
                        category: target.category,
                        isCaution: target.isCaution,
                        cautionReason: target.cautionReason
                    )
                )
            }
            return items

        case .archivesTwoLevel(let labelPrefix):
            guard fm.fileExists(atPath: target.baseURL.path),
                  let dateFolders = try? fm.contentsOfDirectory(
                      at: target.baseURL,
                      includingPropertiesForKeys: [.isDirectoryKey],
                      options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            var items: [ScanItem] = []
            for dateFolder in dateFolders {
                if Task.isCancelled { break }
                let archives = (try? fm.contentsOfDirectory(
                    at: dateFolder,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []

                if archives.isEmpty {
                    if let metrics = DirectorySizeCalculator.calculateMetrics(for: dateFolder) {
                        items.append(
                            ScanItem(
                                name: dateFolder.lastPathComponent,
                                subtitle: "\(labelPrefix) • \(abbreviateHomePath(dateFolder.path))",
                                url: dateFolder,
                                sizeBytes: metrics.sizeBytes,
                                lastModified: metrics.lastModified,
                                category: target.category,
                                isCaution: target.isCaution,
                                cautionReason: target.cautionReason
                            )
                        )
                    }
                } else {
                    for archiveURL in archives {
                        if Task.isCancelled { break }
                        guard let metrics = DirectorySizeCalculator.calculateMetrics(for: archiveURL) else {
                            continue
                        }
                        items.append(
                            ScanItem(
                                name: archiveURL.lastPathComponent,
                                subtitle: "\(labelPrefix) (\(dateFolder.lastPathComponent))",
                                url: archiveURL,
                                sizeBytes: metrics.sizeBytes,
                                lastModified: metrics.lastModified,
                                category: target.category,
                                isCaution: target.isCaution,
                                cautionReason: target.cautionReason
                            )
                        )
                    }
                }
            }
            return items

        case .tmpPrefixMatch(let directoryURL, let prefixes, let labelPrefix):
            guard let children = try? fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var items: [ScanItem] = []
            for childURL in children {
                if Task.isCancelled { break }
                let name = childURL.lastPathComponent
                guard prefixes.contains(where: { name.hasPrefix($0) }),
                      let metrics = DirectorySizeCalculator.calculateMetrics(for: childURL) else {
                    continue
                }
                items.append(
                    ScanItem(
                        name: name,
                        subtitle: labelPrefix,
                        url: childURL,
                        sizeBytes: metrics.sizeBytes,
                        lastModified: metrics.lastModified,
                        category: target.category,
                        isCaution: target.isCaution,
                        cautionReason: target.cautionReason
                    )
                )
            }
            return items
        }
    }

    private static func formatFriendlyName(for url: URL, labelPrefix: String) -> String {
        let rawName = url.lastPathComponent

        // CoreSimulator Devices の場合は device.plist から端末名を取得できる場合は付与
        if labelPrefix == "Simulator Device" {
            let plistURL = url.appendingPathComponent("device.plist")
            if let dict = NSDictionary(contentsOf: plistURL),
               let deviceName = dict["name"] as? String {
                return "\(deviceName) (\(rawName.prefix(8)))"
            }
        }

        // HuggingFace models--org--repo 形式を見やすく整形
        if rawName.hasPrefix("models--") {
            let formatted = rawName
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
            return formatted
        }

        return rawName
    }

    static func abbreviateHomePath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}

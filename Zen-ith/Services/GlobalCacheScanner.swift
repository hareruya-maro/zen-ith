import Foundation

nonisolated struct CacheScanTarget: Sendable {
    enum Granularity: Sendable {
        case wholeDirectory(displayName: String)
        case subdirectories(labelPrefix: String)
        case simulatorCaches(labelPrefix: String)
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
                baseURL: home("Library/Developer/Xcode/watchOS DeviceSupport"),
                granularity: .subdirectories(labelPrefix: "watchOS DeviceSupport")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/Xcode/tvOS DeviceSupport"),
                granularity: .subdirectories(labelPrefix: "tvOS DeviceSupport")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/Xcode/visionOS DeviceSupport"),
                granularity: .subdirectories(labelPrefix: "visionOS DeviceSupport")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/CoreSimulator/Caches"),
                granularity: .simulatorCaches(labelPrefix: "CoreSimulator Cache")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Developer/CoreSimulator/Devices"),
                granularity: .subdirectories(labelPrefix: "Simulator Device")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Caches/org.swift.swiftpm/repositories"),
                granularity: .subdirectories(labelPrefix: "SwiftPM Repo")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Caches/org.swift.swiftpm/artifacts"),
                granularity: .subdirectories(labelPrefix: "SwiftPM Artifact")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Caches/org.swift.swiftpm/manifests"),
                granularity: .wholeDirectory(displayName: "SwiftPM Manifests Cache")
            ),
            CacheScanTarget(
                category: .xcode,
                baseURL: home("Library/Caches/CocoaPods"),
                granularity: .wholeDirectory(displayName: "CocoaPods Cache")
            ),

            // MARK: - Android / Flutter
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
            CacheScanTarget(
                category: .android,
                baseURL: home(".gradle/daemon"),
                granularity: .subdirectories(labelPrefix: "Gradle Daemon Logs")
            ),
            CacheScanTarget(
                category: .android,
                baseURL: home(".pub-cache"),
                granularity: .wholeDirectory(displayName: "Flutter / Dart Pub Cache")
            ),

            // MARK: - Node.js / Web / E2E ブラウザ
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
                baseURL: home("Library/Caches/ms-playwright-go"),
                granularity: .subdirectories(labelPrefix: "Playwright Go Browser")
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
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home("Library/Caches/turbo"),
                granularity: .wholeDirectory(displayName: "Turborepo Cache")
            ),
            CacheScanTarget(
                category: .nodeWeb,
                baseURL: home("Library/Caches/vercel"),
                granularity: .wholeDirectory(displayName: "Vercel CLI Cache")
            ),

            // MARK: - Python / AI モデルキャッシュ
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
                granularity: .subdirectories(labelPrefix: "Hugging Face Hub"),
                isCaution: true,
                cautionReason: "ダウンロード済みのHugging Faceモデル重みです（削除すると再取得が必要）"
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".cache/huggingface/datasets"),
                granularity: .subdirectories(labelPrefix: "Hugging Face Dataset"),
                isCaution: true,
                cautionReason: "ダウンロード済みのHugging Faceデータセットキャッシュです"
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".cache/torch"),
                granularity: .subdirectories(labelPrefix: "PyTorch Cache"),
                isCaution: true,
                cautionReason: "PyTorch Hub等の学習済みモデル重みキャッシュです"
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".ollama/models"),
                granularity: .wholeDirectory(displayName: "Ollama Local Models"),
                isCaution: true,
                cautionReason: "ローカルLLMの重みデータです（削除すると再pullが必要になります）"
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".lmstudio/models"),
                granularity: .subdirectories(labelPrefix: "LM Studio Model"),
                isCaution: true,
                cautionReason: "LM StudioのローカルLLM重みデータです"
            ),
            CacheScanTarget(
                category: .pythonAI,
                baseURL: home(".cache/whisper"),
                granularity: .subdirectories(labelPrefix: "Whisper Model"),
                isCaution: true,
                cautionReason: "OpenAI Whisper音声認識モデルの重みデータです"
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
                baseURL: home("Library/Caches/Google"),
                granularity: .subdirectories(labelPrefix: "Google IDE Cache")
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Logs/Google"),
                granularity: .subdirectories(labelPrefix: "Google IDE Logs")
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
            ),
            CacheScanTarget(
                category: .ideEditor,
                baseURL: home("Library/Caches/dev.zed.Zed"),
                granularity: .wholeDirectory(displayName: "Zed Editor Cache")
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

        case .simulatorCaches(let labelPrefix):
            return scanSimulatorCaches(baseURL: target.baseURL, labelPrefix: labelPrefix, target: target)

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
                                subtitle: "\(labelPrefix) (\(dateFolder.lastPathComponent)) • \(abbreviateHomePath(archiveURL.path))",
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
        }
    }

    /// `~/Library/Developer/CoreSimulator/Caches` を走査し、`dyld/<hostBuild>/com.apple.CoreSimulator.SimRuntime.*` があればOSバージョン単位に展開する
    private static func scanSimulatorCaches(
        baseURL: URL,
        labelPrefix: String,
        target: CacheScanTarget
    ) -> [ScanItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseURL.path),
              let topChildren = try? fm.contentsOfDirectory(
                  at: baseURL,
                  includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var items: [ScanItem] = []

        for childURL in topChildren {
            if Task.isCancelled { break }

            // dyld フォルダの場合は <macOSBuild>/com.apple.CoreSimulator.SimRuntime.* まで掘ってOSごとに表示
            if childURL.lastPathComponent == "dyld",
               let buildFolders = try? fm.contentsOfDirectory(
                   at: childURL,
                   includingPropertiesForKeys: [.isDirectoryKey],
                   options: [.skipsHiddenFiles]
               ),
               !buildFolders.isEmpty {
                var expandedAnyRuntime = false

                for buildFolder in buildFolders {
                    let runtimeFolders = (try? fm.contentsOfDirectory(
                        at: buildFolder,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []

                    for runtimeURL in runtimeFolders {
                        if Task.isCancelled { break }
                        guard let metrics = DirectorySizeCalculator.calculateMetrics(for: runtimeURL) else {
                            continue
                        }
                        expandedAnyRuntime = true
                        let osLabel = parseSimulatorRuntimeIdentifier(runtimeURL.lastPathComponent)
                            ?? runtimeURL.lastPathComponent
                        items.append(
                            ScanItem(
                                name: "dyld Cache — \(osLabel)",
                                subtitle: "\(labelPrefix) (Host \(buildFolder.lastPathComponent)) • \(abbreviateHomePath(runtimeURL.path))",
                                url: runtimeURL,
                                sizeBytes: metrics.sizeBytes,
                                lastModified: metrics.lastModified,
                                category: target.category,
                                isCaution: target.isCaution,
                                cautionReason: target.cautionReason
                            )
                        )
                    }
                }

                if expandedAnyRuntime {
                    continue
                }
            }

            // それ以外のキャッシュフォルダ
            guard let metrics = DirectorySizeCalculator.calculateMetrics(for: childURL) else {
                continue
            }
            let osLabel = parseSimulatorRuntimeIdentifier(childURL.lastPathComponent)
            let displayName = if let osLabel {
                "\(childURL.lastPathComponent) — \(osLabel)"
            } else {
                childURL.lastPathComponent
            }

            items.append(
                ScanItem(
                    name: displayName,
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
    }

    static func formatFriendlyName(for url: URL, labelPrefix: String) -> String {
        let rawName = url.lastPathComponent

        // CoreSimulator Devices の場合は device.plist から端末名とOSバージョン（runtime）を取得
        if labelPrefix == "Simulator Device" {
            let plistURL = url.appendingPathComponent("device.plist")
            if let dict = NSDictionary(contentsOf: plistURL) {
                let deviceName = (dict["name"] as? String) ?? rawName
                let runtimeRaw = dict["runtime"] as? String
                let osLabel = runtimeRaw.flatMap { parseSimulatorRuntimeIdentifier($0) }

                if let osLabel {
                    return "\(deviceName) [\(osLabel)] (\(rawName.prefix(8)))"
                } else {
                    return "\(deviceName) (\(rawName.prefix(8)))"
                }
            }
        }

        // Android AVD の場合は .avd/config.ini から API レベル / Android OS バージョンを取得
        if labelPrefix == "Android AVD" {
            let avdBase = url.deletingPathExtension().lastPathComponent
            let configURL = url.appendingPathComponent("config.ini")
            if let configText = try? String(contentsOf: configURL, encoding: .utf8),
               let apiLevel = extractAndroidAPILevel(from: configText) {
                return "\(avdBase) [\(formatAndroidVersion(apiLevel: apiLevel))]"
            }
            return avdBase
        }

        // Android System Image (android-34 等)
        if labelPrefix == "Android System Image" {
            if let apiLevel = extractAndroidAPILevel(from: rawName) {
                return "\(rawName) [\(formatAndroidVersion(apiLevel: apiLevel))]"
            }
        }

        // HuggingFace models--org--repo / datasets--org--repo 形式を見やすく整形
        if rawName.hasPrefix("models--") {
            let formatted = rawName
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
            return formatted
        }
        if rawName.hasPrefix("datasets--") {
            let formatted = rawName
                .replacingOccurrences(of: "datasets--", with: "")
                .replacingOccurrences(of: "--", with: "/")
            return "Dataset: \(formatted)"
        }

        // Playwright ブラウザバイナリ (例: chromium-1140, firefox-1465, webkit-2083)
        if labelPrefix.contains("Playwright") {
            let parts = rawName.components(separatedBy: "-")
            if parts.count == 2, parts[1].allSatisfy(\.isNumber) {
                let engine = parts[0].capitalized
                return "Playwright \(engine) (r\(parts[1]))"
            }
        }

        // JetBrains / Android Studio バージョンフォルダ整形 (例: IntelliJIdea2024.3 -> IntelliJ IDEA 2024.3)
        if labelPrefix.contains("JetBrains") || labelPrefix.contains("Google IDE") {
            if let formattedIDE = formatIDEDirectoryName(rawName) {
                return formattedIDE
            }
        }

        return rawName
    }

    static func formatIDEDirectoryName(_ rawName: String) -> String? {
        let prefixes: [(prefix: String, label: String)] = [
            ("IntelliJIdea", "IntelliJ IDEA"),
            ("IdeaIC", "IntelliJ IDEA CE"),
            ("WebStorm", "WebStorm"),
            ("PyCharmCE", "PyCharm CE"),
            ("PyCharm", "PyCharm"),
            ("GoLand", "GoLand"),
            ("CLion", "CLion"),
            ("RustRover", "RustRover"),
            ("PhpStorm", "PhpStorm"),
            ("RubyMine", "RubyMine"),
            ("DataGrip", "DataGrip"),
            ("Rider", "Rider"),
            ("AndroidStudio", "Android Studio")
        ]
        for entry in prefixes where rawName.hasPrefix(entry.prefix) {
            let version = String(rawName.dropFirst(entry.prefix.count))
            if !version.isEmpty, version.first?.isNumber == true {
                return "\(entry.label) \(version)"
            }
        }
        return nil
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-18-2` や `com.apple.CoreSimulator.SimRuntime.iOS-17-5.21F79` から `"iOS 18.2"` 等を抽出する
    static func parseSimulatorRuntimeIdentifier(_ identifier: String) -> String? {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        let target: String
        if let range = identifier.range(of: prefix) {
            target = String(identifier[range.upperBound...])
        } else {
            target = identifier
        }

        // 例: "iOS-18-2" または "iOS-17-5.21F79" または "xrOS-2-1"
        let parts = target.components(separatedBy: ".")
        guard let osAndVersion = parts.first else { return nil }
        let buildSuffix = parts.count > 1 ? parts[1] : nil

        let tokens = osAndVersion.components(separatedBy: "-")
        guard tokens.count >= 2 else { return nil }

        let rawOS = tokens[0]
        let osName: String = switch rawOS.lowercased() {
        case "ios": "iOS"
        case "ipad", "ipados": "iPadOS"
        case "watchos": "watchOS"
        case "tvos": "tvOS"
        case "xros", "visionos": "visionOS"
        default: rawOS
        }

        let versionNumbers = tokens.dropFirst().filter { $0.allSatisfy(\.isNumber) }
        guard !versionNumbers.isEmpty else { return nil }
        let versionString = versionNumbers.joined(separator: ".")

        if let buildSuffix, !buildSuffix.isEmpty {
            return "\(osName) \(versionString) (\(buildSuffix))"
        }
        return "\(osName) \(versionString)"
    }

    private static func extractAndroidAPILevel(from text: String) -> Int? {
        let pattern = #"android-(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    static func formatAndroidVersion(apiLevel: Int) -> String {
        let versionMap: [Int: String] = [
            36: "Android 16",
            35: "Android 15",
            34: "Android 14",
            33: "Android 13",
            32: "Android 12L",
            31: "Android 12",
            30: "Android 11",
            29: "Android 10",
            28: "Android 9"
        ]
        if let name = versionMap[apiLevel] {
            return "\(name) / API \(apiLevel)"
        }
        return "API \(apiLevel)"
    }

    static func abbreviateHomePath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}

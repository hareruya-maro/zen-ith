import Foundation

nonisolated struct WorkspaceScanOptions: Sendable {
    let includeRustMavenTarget: Bool
    let includeBuildGradleDirs: Bool

    init(includeRustMavenTarget: Bool = true, includeBuildGradleDirs: Bool = true) {
        self.includeRustMavenTarget = includeRustMavenTarget
        self.includeBuildGradleDirs = includeBuildGradleDirs
    }
}

nonisolated struct WorkspaceCandidate: Sendable {
    let url: URL
    let projectRootURL: URL
    let projectName: String
    let kindLabel: String
}

nonisolated enum WorkspaceDeepScanner {
    private static let frontendCacheNames: Set<String> = [
        ".next", ".nuxt", ".turbo", ".parcel-cache", ".astro"
    ]

    private static let ignoredTraversalDirectories: Set<String> = [
        ".git", ".hg", ".svn", ".DS_Store", ".Trash", "Library", ".build"
    ]

    private static let projectIndicatorFiles: [String] = [
        ".git/index",
        ".git/HEAD",
        "package.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "bun.lockb",
        "Podfile",
        "Podfile.lock",
        "pyproject.toml",
        "requirements.txt",
        "uv.lock",
        "Cargo.toml",
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "Gemfile",
        "main.tf"
    ]

    @concurrent
    static func scanWorkspaces(
        rootDirectories: [URL],
        options: WorkspaceScanOptions = WorkspaceScanOptions()
    ) async -> [ScanItem] {
        // 1. 各ルートディレクトリを並列走査してターゲットフォルダ一覧を高速収集
        let candidates = await withTaskGroup(of: [WorkspaceCandidate].self) { group in
            for rootURL in rootDirectories {
                group.addTask {
                    if Task.isCancelled { return [] }
                    return discoverCandidates(in: rootURL, options: options)
                }
            }

            var seenPaths: Set<String> = []
            var allCandidates: [WorkspaceCandidate] = []
            for await batch in group {
                for candidate in batch {
                    let standardized = candidate.url.standardizedFileURL.path
                    if seenPaths.insert(standardized).inserted {
                        allCandidates.append(candidate)
                    }
                }
            }
            return allCandidates
        }

        guard !candidates.isEmpty, !Task.isCancelled else { return [] }

        // 2. 検出した各ターゲットフォルダのサイズとプロジェクト最終更新日時を並列計算
        return await withTaskGroup(of: ScanItem?.self) { group in
            for candidate in candidates {
                group.addTask {
                    if Task.isCancelled { return nil }
                    guard let metrics = DirectorySizeCalculator.calculateMetrics(for: candidate.url) else {
                        return nil
                    }
                    let lastActiveDate = resolveProjectLastActiveDate(
                        projectRoot: candidate.projectRootURL,
                        artifactDate: metrics.lastModified
                    )
                    let displayRelative = GlobalCacheScanner.abbreviateHomePath(candidate.url.path)
                    let itemTitle = "\(candidate.projectName) / \(candidate.url.lastPathComponent)"

                    return ScanItem(
                        name: itemTitle,
                        subtitle: displayRelative,
                        url: candidate.url,
                        sizeBytes: metrics.sizeBytes,
                        lastModified: lastActiveDate,
                        category: .workspace,
                        smartBadge: .workspaceArtifact(kindLabel: candidate.kindLabel)
                    )
                }
            }

            var results: [ScanItem] = []
            for await item in group {
                if let item {
                    results.append(item)
                }
            }
            return results.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    /// 単一のワークスペースルート配下を再帰探索し、ターゲットを見つけたら skipDescendants() で深掘りを止める
    static func discoverCandidates(
        in rootURL: URL,
        options: WorkspaceScanOptions
    ) -> [WorkspaceCandidate] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else { return [] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [WorkspaceCandidate] = []

        for case let currentURL as URL in enumerator {
            if Task.isCancelled { break }

            guard let values = try? currentURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            guard values.isDirectory == true else {
                continue
            }

            let dirName = currentURL.lastPathComponent

            // .git 等の探索不要ディレクトリは即スキップ
            if ignoredTraversalDirectories.contains(dirName) {
                enumerator.skipDescendants()
                continue
            }

            if let match = matchWorkspaceTarget(
                directoryURL: currentURL,
                dirName: dirName,
                options: options,
                fileManager: fm
            ) {
                // ターゲットを見つけたらそれ以上深い階層（ネストされた node_modules 等）へは潜らない
                enumerator.skipDescendants()
                candidates.append(match)
            }
        }

        return candidates
    }

    static func matchWorkspaceTarget(
        directoryURL: URL,
        dirName: String,
        options: WorkspaceScanOptions,
        fileManager fm: FileManager = .default
    ) -> WorkspaceCandidate? {
        let parentURL = directoryURL.deletingLastPathComponent()
        let parentName = parentURL.lastPathComponent

        // 1. node_modules
        if dirName == "node_modules" {
            return WorkspaceCandidate(
                url: directoryURL,
                projectRootURL: parentURL,
                projectName: parentName,
                kindLabel: "Node.js"
            )
        }

        // 2. Pods / ios/Pods
        if dirName == "Pods" {
            let hasPodfileInParent = fm.fileExists(atPath: parentURL.appendingPathComponent("Podfile").path)
            if parentName.lowercased() == "ios" || parentName.lowercased() == "macos" {
                let grandParent = parentURL.deletingLastPathComponent()
                return WorkspaceCandidate(
                    url: directoryURL,
                    projectRootURL: grandParent,
                    projectName: "\(grandParent.lastPathComponent)/\(parentName)",
                    kindLabel: "CocoaPods"
                )
            } else if hasPodfileInParent {
                return WorkspaceCandidate(
                    url: directoryURL,
                    projectRootURL: parentURL,
                    projectName: parentName,
                    kindLabel: "CocoaPods"
                )
            }
        }

        // 3. Python 仮想環境 (.venv / venv)
        if dirName == ".venv" || dirName == "venv" {
            let isVenv = dirName == ".venv"
                || fm.fileExists(atPath: directoryURL.appendingPathComponent("pyvenv.cfg").path)
                || fm.fileExists(atPath: directoryURL.appendingPathComponent("bin/python").path)
            if isVenv {
                return WorkspaceCandidate(
                    url: directoryURL,
                    projectRootURL: parentURL,
                    projectName: parentName,
                    kindLabel: "Python venv"
                )
            }
        }

        // 4. フロントエンドビルドキャッシュ (.next, .nuxt, .turbo, .parcel-cache, .astro)
        if frontendCacheNames.contains(dirName) {
            return WorkspaceCandidate(
                url: directoryURL,
                projectRootURL: parentURL,
                projectName: parentName,
                kindLabel: "Frontend Cache"
            )
        }

        // 5. Ruby Bundler (vendor/bundle)
        if dirName == "bundle" && parentName == "vendor" {
            let projectRoot = parentURL.deletingLastPathComponent()
            return WorkspaceCandidate(
                url: directoryURL,
                projectRootURL: projectRoot,
                projectName: projectRoot.lastPathComponent,
                kindLabel: "Ruby Bundler"
            )
        }

        // 6. Terraform (.terraform)
        if dirName == ".terraform" {
            return WorkspaceCandidate(
                url: directoryURL,
                projectRootURL: parentURL,
                projectName: parentName,
                kindLabel: "Terraform"
            )
        }

        // 7. Rust / Maven (target ※任意ON/OFF)
        if options.includeRustMavenTarget && dirName == "target" {
            let hasCargo = fm.fileExists(atPath: parentURL.appendingPathComponent("Cargo.toml").path)
            let hasMaven = fm.fileExists(atPath: parentURL.appendingPathComponent("pom.xml").path)
            if hasCargo || hasMaven {
                return WorkspaceCandidate(
                    url: directoryURL,
                    projectRootURL: parentURL,
                    projectName: parentName,
                    kindLabel: hasCargo ? "Rust target" : "Maven target"
                )
            }
        }

        // 8. Android / Java / C++ (build, .gradle, .cxx ※任意ON/OFF)
        if options.includeBuildGradleDirs {
            if dirName == ".gradle" || dirName == ".cxx" {
                return WorkspaceCandidate(
                    url: directoryURL,
                    projectRootURL: parentURL,
                    projectName: parentName,
                    kindLabel: dirName == ".gradle" ? "Gradle" : "C++ (.cxx)"
                )
            }
            if dirName == "build" {
                let buildMarkers = [
                    "build.gradle",
                    "build.gradle.kts",
                    "settings.gradle",
                    "settings.gradle.kts",
                    "CMakeLists.txt",
                    "pubspec.yaml"
                ]
                let isBuildProject = buildMarkers.contains { marker in
                    fm.fileExists(atPath: parentURL.appendingPathComponent(marker).path)
                }
                if isBuildProject {
                    return WorkspaceCandidate(
                        url: directoryURL,
                        projectRootURL: parentURL,
                        projectName: parentName,
                        kindLabel: "Build Output"
                    )
                }
            }
        }

        return nil
    }

    /// プロジェクトルート内の .git/index や package.json 等の更新日時と対象フォルダの更新日時を比較し、「最後に触った日」を算出する
    static func resolveProjectLastActiveDate(projectRoot: URL, artifactDate: Date) -> Date {
        var latestDate = artifactDate

        for relativePath in projectIndicatorFiles {
            let fileURL = projectRoot.appendingPathComponent(relativePath)
            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate > latestDate {
                latestDate = modDate
            }
        }

        return latestDate
    }
}

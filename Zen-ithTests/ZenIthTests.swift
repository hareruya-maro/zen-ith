import Foundation
import Testing
@testable import Zen_ith

struct ZenIthTests {
    @Test("インストーラーのファイル名からコア名を抽出しインストール済みアプリと照合できる")
    func installerMatching() {
        let installedApps: [(original: String, normalized: String)] = [
            ("Visual Studio Code", DownloadsSmartScanner.normalizeCoreName("Visual Studio Code")),
            ("Docker", DownloadsSmartScanner.normalizeCoreName("Docker")),
            ("Slack", DownloadsSmartScanner.normalizeCoreName("Slack")),
            ("Google Chrome", DownloadsSmartScanner.normalizeCoreName("Google Chrome"))
        ]

        #expect(
            DownloadsSmartScanner.matchInstalledApp(
                forInstallerFileName: "VisualStudioCode-darwin-arm64.dmg",
                installedApps: installedApps
            ) == "Visual Studio Code"
        )
        #expect(
            DownloadsSmartScanner.matchInstalledApp(
                forInstallerFileName: "Docker.dmg",
                installedApps: installedApps
            ) == "Docker"
        )
        #expect(
            DownloadsSmartScanner.matchInstalledApp(
                forInstallerFileName: "Slack-4.38.dmg",
                installedApps: installedApps
            ) == "Slack"
        )
        #expect(
            DownloadsSmartScanner.matchInstalledApp(
                forInstallerFileName: "UnknownTool-1.0.0-arm64.dmg",
                installedApps: installedApps
            ) == nil
        )
    }

    @Test("圧縮アーカイブの拡張子（複合拡張子含む）からベースフォルダ名を抽出できる")
    func archiveBaseNameExtraction() {
        #expect(DownloadsSmartScanner.extractArchiveBaseName(from: "project-assets.zip") == "project-assets")
        #expect(DownloadsSmartScanner.extractArchiveBaseName(from: "release-source.tar.gz") == "release-source")
        #expect(DownloadsSmartScanner.extractArchiveBaseName(from: "backup.tgz") == "backup")
        #expect(DownloadsSmartScanner.extractArchiveBaseName(from: "document.pdf") == nil)
    }

    @Test("重複ダウンロードファイルの命名パターンから元ファイル名を特定できる")
    func duplicatePatternDetection() {
        #expect(DownloadsSmartScanner.extractDuplicateBaseFileName(from: "請求書_2026 (1).pdf") == "請求書_2026.pdf")
        #expect(DownloadsSmartScanner.extractDuplicateBaseFileName(from: "photo(2).jpg") == "photo.jpg")
        #expect(DownloadsSmartScanner.extractDuplicateBaseFileName(from: "archive 2.zip") == "archive.zip")
        #expect(DownloadsSmartScanner.extractDuplicateBaseFileName(from: "design のコピー.png") == "design.png")
        #expect(DownloadsSmartScanner.extractDuplicateBaseFileName(from: "normal_file.pdf") == nil)
    }

    @Test("3段階重複検証（サイズ完全一致＋SHA-256ハッシュ一致）で誤爆しない")
    func duplicateVerificationWithTempFiles() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("zenith-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let origURL = tempDir.appendingPathComponent("invoice.pdf")
        let dupURL = tempDir.appendingPathComponent("invoice (1).pdf")
        let sameSizeDiffContentURL = tempDir.appendingPathComponent("invoice (2).pdf")

        let contentA = Data("Zen-ith exact duplicate payload 1234567890".utf8)
        let contentB = Data("Zen-ith DIFFERENT-BYTES payload 1234567890".utf8)
        #expect(contentA.count == contentB.count)

        try contentA.write(to: origURL)
        try contentA.write(to: dupURL)
        try contentB.write(to: sameSizeDiffContentURL)

        // 完全に同一内容の (1) は true
        #expect(DownloadsSmartScanner.isVerifiedExactDuplicate(candidateURL: dupURL, originalURL: origURL) == true)

        // バイト数が同じでも中身が1バイトでも異なる (2) は false（誤爆ゼロ）
        #expect(DownloadsSmartScanner.isVerifiedExactDuplicate(candidateURL: sameSizeDiffContentURL, originalURL: origURL) == false)
    }

    @Test("スマートフィルタが確定バッジ・経過日数・要注意フラグを正しく判定する")
    func smartFilterRules() {
        let now = Date()
        let fiveDaysAgo = now.addingTimeInterval(-5 * 86_400)
        let fortyDaysAgo = now.addingTimeInterval(-40 * 86_400)

        let recentInstalledDmg = ScanItem(
            name: "Docker.dmg",
            subtitle: "Downloads",
            url: URL(fileURLWithPath: "/tmp/Docker.dmg"),
            sizeBytes: 600_000_000,
            lastModified: fiveDaysAgo,
            category: .downloads,
            smartBadge: .installedApp(appName: "Docker")
        )

        let recentCache = ScanItem(
            name: "RecentProject-abc",
            subtitle: "DerivedData",
            url: URL(fileURLWithPath: "/tmp/RecentProject-abc"),
            sizeBytes: 1_200_000_000,
            lastModified: fiveDaysAgo,
            category: .xcode
        )

        let staleCache = ScanItem(
            name: "OldProject-xyz",
            subtitle: "DerivedData",
            url: URL(fileURLWithPath: "/tmp/OldProject-xyz"),
            sizeBytes: 2_500_000_000,
            lastModified: fortyDaysAgo,
            category: .xcode
        )

        let cautionArchive = ScanItem(
            name: "Release.xcarchive",
            subtitle: "Archives",
            url: URL(fileURLWithPath: "/tmp/Release.xcarchive"),
            sizeBytes: 800_000_000,
            lastModified: fortyDaysAgo,
            category: .xcode,
            isCaution: true
        )

        // ✨推奨: 確定バッジ付きは経過5日でもON、キャッシュは30日以上のみON、要注意項目は常にOFF
        #expect(recentInstalledDmg.matchesFilter(.recommended, now: now) == true)
        #expect(recentCache.matchesFilter(.recommended, now: now) == false)
        #expect(staleCache.matchesFilter(.recommended, now: now) == true)
        #expect(cautionArchive.matchesFilter(.recommended, now: now) == false)

        // すべて: 要注意項目を除いてすべてON
        #expect(recentCache.matchesFilter(.all, now: now) == true)
        #expect(cautionArchive.matchesFilter(.all, now: now) == false)
    }

    @Test("ワークスペース深層スキャンがネストされたnode_modulesをスキップし、各種ターゲットを正確に検出する")
    func workspaceDeepScanDiscovery() throws {
        let fm = FileManager.default
        let rootDir = fm.temporaryDirectory.appendingPathComponent("zenith-ws-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootDir) }

        // 1. Webアプリ: node_modules (内部にネストされた node_modules を含む) + .next
        let webApp = rootDir.appendingPathComponent("web-app", isDirectory: true)
        let nestedNodeModules = webApp.appendingPathComponent("node_modules/pkg-a/node_modules", isDirectory: true)
        let nextCache = webApp.appendingPathComponent(".next", isDirectory: true)
        try fm.createDirectory(at: nestedNodeModules, withIntermediateDirectories: true)
        try fm.createDirectory(at: nextCache, withIntermediateDirectories: true)

        // 2. React Native アプリ: ios/Pods + vendor/bundle
        let rnApp = rootDir.appendingPathComponent("mobile-app", isDirectory: true)
        let iosPods = rnApp.appendingPathComponent("ios/Pods", isDirectory: true)
        let rubyBundle = rnApp.appendingPathComponent("vendor/bundle", isDirectory: true)
        try fm.createDirectory(at: iosPods, withIntermediateDirectories: true)
        try fm.createDirectory(at: rubyBundle, withIntermediateDirectories: true)

        // 3. Rust プロジェクト: Cargo.toml がある場合の target と、Cargo.toml がない無関係な target
        let rustApp = rootDir.appendingPathComponent("rust-cli", isDirectory: true)
        try fm.createDirectory(at: rustApp.appendingPathComponent("target", isDirectory: true), withIntermediateDirectories: true)
        try Data("[package]\nname = \"cli\"".utf8).write(to: rustApp.appendingPathComponent("Cargo.toml"))

        let normalFolder = rootDir.appendingPathComponent("docs-site", isDirectory: true)
        try fm.createDirectory(at: normalFolder.appendingPathComponent("target", isDirectory: true), withIntermediateDirectories: true)

        let candidates = WorkspaceDeepScanner.discoverCandidates(
            in: rootDir,
            options: WorkspaceScanOptions(includeRustMavenTarget: true, includeBuildGradleDirs: true)
        )

        let detectedPaths = Set(candidates.map { $0.url.standardizedFileURL.path })

        // ルートの node_modules は検出され、ネストされた pkg-a/node_modules はスキップされていること
        #expect(detectedPaths.contains(webApp.appendingPathComponent("node_modules").standardizedFileURL.path))
        #expect(!detectedPaths.contains(nestedNodeModules.standardizedFileURL.path))
        #expect(detectedPaths.contains(nextCache.standardizedFileURL.path))
        #expect(detectedPaths.contains(iosPods.standardizedFileURL.path))
        #expect(detectedPaths.contains(rubyBundle.standardizedFileURL.path))
        #expect(detectedPaths.contains(rustApp.appendingPathComponent("target").standardizedFileURL.path))
        // Cargo.toml / pom.xml のない docs-site/target は誤検出されないこと
        #expect(!detectedPaths.contains(normalFolder.appendingPathComponent("target").standardizedFileURL.path))
    }

    @Test("Docker system df のJSON出力パースと prune 引数・Local Volumes保護が仕様通り動作する")
    func dockerDfParsingAndPruneArgs() {
        let sampleLines = [
            #"{"Active":"1","Reclaimable":"2.5GB (80%)","Size":"3.1GB","TotalCount":"6","Type":"Images"}"#,
            #"{"Active":"0","Reclaimable":"120MB (100%)","Size":"120MB","TotalCount":"3","Type":"Containers"}"#,
            #"{"Active":"1","Reclaimable":"850MB (50%)","Size":"1.7GB","TotalCount":"4","Type":"Local Volumes"}"#,
            #"{"Active":"0","Reclaimable":"5.4GB","Size":"5.4GB","TotalCount":"32","Type":"Build Cache"}"#
        ]

        let items = DockerScanner.parseDockerSystemDfLines(sampleLines)
        #expect(items.count == 4)

        // 最大サイズの Build Cache (5.4GB) が先頭にソートされる
        #expect(items.first?.name == DockerResourceType.buildCache.displayName)
        #expect(items.first?.sizeBytes == 5_400_000_000)

        // Local Volumes は isCaution == true であり、スマートフィルタで自動選択されない
        let volumesItem = items.first { $0.id == "docker:Local Volumes" }
        #expect(volumesItem?.isCaution == true)
        #expect(volumesItem?.matchesFilter(.recommended) == false)
        #expect(volumesItem?.matchesFilter(.all) == false)

        // Build Cache / Images / Containers はスマートフィルタで選択され、until=XXh 引数にマッピングされる
        let imagesItem = items.first { $0.id == "docker:Images" }
        #expect(imagesItem?.matchesFilter(.recommended) == true)
        #expect(DockerResourceType.images.pruneArguments(for: .recommended) == ["image", "prune", "-a", "--filter", "until=720h", "-f"])
        #expect(DockerResourceType.buildCache.pruneArguments(for: .olderThan90Days) == ["builder", "prune", "--filter", "until=2160h", "-f"])
        #expect(DockerResourceType.localVolumes.pruneArguments(for: .all) == ["volume", "prune", "-f"])
    }

    @Test("定期スキャン間隔設定と容量アラート通知のクールダウン制御が正しく動作する")
    func scheduleIntervalAndCapacityAlertRules() {
        #expect(ScanScheduleInterval.manual.timeIntervalSeconds == nil)
        #expect(ScanScheduleInterval.every1Hour.timeIntervalSeconds == 3_600)
        #expect(ScanScheduleInterval.every6Hours.timeIntervalSeconds == 21_600)
        #expect(ScanScheduleInterval.daily.timeIntervalSeconds == 86_400)

        let now = Date()
        let fiftyFiveGB: Int64 = 55_000_000_000
        let twentyGB: Int64 = 20_000_000_000

        // OFF (thresholdGB == 0) の場合は通知しない
        #expect(
            NotificationAndLaunchService.shouldSendCapacityAlert(
                totalBytes: fiftyFiveGB,
                thresholdGB: 0,
                lastNotifiedDate: nil,
                now: now
            ) == false
        )

        // 閾値未満の場合は通知しない
        #expect(
            NotificationAndLaunchService.shouldSendCapacityAlert(
                totalBytes: twentyGB,
                thresholdGB: 30,
                lastNotifiedDate: nil,
                now: now
            ) == false
        )

        // 閾値超過かつ初回は通知する
        #expect(
            NotificationAndLaunchService.shouldSendCapacityAlert(
                totalBytes: fiftyFiveGB,
                thresholdGB: 50,
                lastNotifiedDate: nil,
                now: now
            ) == true
        )

        // クールダウン期間内（例: 1時間前）は重複通知を抑止する
        let oneHourAgo = now.addingTimeInterval(-3_600)
        #expect(
            NotificationAndLaunchService.shouldSendCapacityAlert(
                totalBytes: fiftyFiveGB,
                thresholdGB: 50,
                lastNotifiedDate: oneHourAgo,
                now: now
            ) == false
        )

        // クールダウン経過後（例: 7時間前）は再通知する
        let sevenHoursAgo = now.addingTimeInterval(-7 * 3_600)
        #expect(
            NotificationAndLaunchService.shouldSendCapacityAlert(
                totalBytes: fiftyFiveGB,
                thresholdGB: 50,
                lastNotifiedDate: sevenHoursAgo,
                now: now
            ) == true
        )
    }

    @Test("SimulatorのランタイムIDやAndroidシステムイメージ名からOSバージョンを抽出できる")
    func simulatorOSVersionParsing() throws {
        #expect(
            GlobalCacheScanner.parseSimulatorRuntimeIdentifier("com.apple.CoreSimulator.SimRuntime.iOS-18-2")
            == "iOS 18.2"
        )
        #expect(
            GlobalCacheScanner.parseSimulatorRuntimeIdentifier("com.apple.CoreSimulator.SimRuntime.iOS-17-5.21F79")
            == "iOS 17.5 (21F79)"
        )
        #expect(
            GlobalCacheScanner.parseSimulatorRuntimeIdentifier("com.apple.CoreSimulator.SimRuntime.xrOS-2-1")
            == "visionOS 2.1"
        )
        #expect(
            GlobalCacheScanner.parseSimulatorRuntimeIdentifier("com.apple.CoreSimulator.SimRuntime.watchOS-11-0")
            == "watchOS 11.0"
        )

        // Simulator Device の device.plist から端末名＋OS名を取得できるか検証
        let fm = FileManager.default
        let tempSimDir = fm.temporaryDirectory.appendingPathComponent("12345678-ABCD-EF00", isDirectory: true)
        try fm.createDirectory(at: tempSimDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempSimDir) }

        let plistDict: NSDictionary = [
            "name": "iPhone 16 Pro",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
        ]
        plistDict.write(to: tempSimDir.appendingPathComponent("device.plist"), atomically: true)

        let friendly = GlobalCacheScanner.formatFriendlyName(for: tempSimDir, labelPrefix: "Simulator Device")
        #expect(friendly == "iPhone 16 Pro [iOS 18.2] (12345678)")
    }

    @Test("AIアドバイザーがキャッシュ種別や要注意項目ごとに適切な安全性診断と復元方法を生成する")
    func aiAdvisorAnalysisTest() async {
        let derivedDataItem = ScanItem(
            name: "Zen-ith-abcdef",
            subtitle: "DerivedData • ~/Library/Developer/Xcode/DerivedData/Zen-ith-abcdef",
            url: URL(fileURLWithPath: "/Users/test/Library/Developer/Xcode/DerivedData/Zen-ith-abcdef"),
            sizeBytes: 1_500_000_000,
            lastModified: Date(),
            category: .xcode
        )
        let derivedAnalysis = AIAdvisorService.generateInstantAnalysis(for: derivedDataItem)
        #expect(derivedAnalysis.safetyLevel == .safe)
        #expect(derivedAnalysis.whatIsThis.contains("DerivedData"))

        let dockerVolumeItem = ScanItem(
            id: "docker:Local Volumes",
            name: DockerResourceType.localVolumes.displayName,
            subtitle: "合計 2件",
            url: URL(fileURLWithPath: "/Users/test/.docker/volumes"),
            sizeBytes: 800_000_000,
            lastModified: Date(),
            category: .docker,
            targetKind: .dockerPrune(.localVolumes),
            isCaution: true
        )
        let volumeAnalysis = AIAdvisorService.generateInstantAnalysis(for: dockerVolumeItem)
        #expect(volumeAnalysis.safetyLevel == .critical)

        let reply = await AIAdvisorService.askAdvisor(
            item: derivedDataItem,
            question: "消した後に元に戻すコマンドを教えて",
            provider: .offlineSmart,
            localCLI: .claude,
            ollamaModel: "",
            geminiAPIKey: ""
        )
        #expect(reply.isUser == false)
        #expect(reply.text.contains("Xcode"))
    }

    @Test("Mac空き容量ゲージの回復予測計算と検索キーワード絞り込みが正しく動作する")
    func diskSpaceAndSearchQueryTest() {
        let disk = DiskSpaceMetrics(
            totalBytes: 500_000_000_000,
            availableBytes: 50_000_000_000
        )
        #expect(disk.usedBytes == 450_000_000_000)
        #expect(disk.projectedAvailableBytes(reclaiming: 25_000_000_000) == 75_000_000_000)
        #expect(abs(disk.reclaimableFraction(reclaiming: 50_000_000_000) - 0.1) < 0.0001)

        let simItem = ScanItem(
            name: "iPhone 15 Pro [iOS 17.5] (ABCDEF12)",
            subtitle: "Simulator Device • ~/Library/Developer/CoreSimulator/Devices/ABCDEF12",
            url: URL(fileURLWithPath: "/Users/test/Library/Developer/CoreSimulator/Devices/ABCDEF12"),
            sizeBytes: 4_200_000_000,
            lastModified: Date(),
            category: .xcode
        )
        #expect(simItem.matchesSearchQuery("iOS 17"))
        #expect(simItem.matchesSearchQuery("iphone simulator"))
        #expect(!simItem.matchesSearchQuery("android"))

        // 追加キャッシュの表示名整形検証 (Playwright / JetBrains / HuggingFace Dataset)
        #expect(
            GlobalCacheScanner.formatFriendlyName(
                for: URL(fileURLWithPath: "/Users/test/Library/Caches/ms-playwright/chromium-1140"),
                labelPrefix: "Playwright Browser"
            ) == "Playwright Chromium (r1140)"
        )
        #expect(
            GlobalCacheScanner.formatFriendlyName(
                for: URL(fileURLWithPath: "/Users/test/Library/Caches/JetBrains/IntelliJIdea2024.3"),
                labelPrefix: "JetBrains Cache"
            ) == "IntelliJ IDEA 2024.3"
        )
        #expect(
            GlobalCacheScanner.formatFriendlyName(
                for: URL(fileURLWithPath: "/Users/test/.cache/huggingface/datasets/datasets--wikimedia--wikipedia"),
                labelPrefix: "Hugging Face Dataset"
            ) == "Dataset: wikimedia/wikipedia"
        )
    }

    @Test("セマンティックバージョン比較（vプレフィックス対応）が正しく判定される")
    func versionComparatorTest() {
        #expect(VersionComparator.isNewer(candidate: "v0.2.0", than: "0.1.0"))
        #expect(VersionComparator.isNewer(candidate: "1.0.0", than: "0.9.9"))
        #expect(!VersionComparator.isNewer(candidate: "v0.1.0", than: "0.1.0"))
        #expect(!VersionComparator.isNewer(candidate: "v0.0.9", than: "0.1.0"))
    }
}



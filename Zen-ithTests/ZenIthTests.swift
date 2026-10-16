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
}

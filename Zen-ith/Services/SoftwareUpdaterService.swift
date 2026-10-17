import AppKit
import Combine
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

nonisolated struct GitHubReleaseDTO: Decodable, Sendable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
    }
}

nonisolated enum VersionComparator {
    /// `"v1.2.0"` と `"1.1.0"` のようなバージョン文字列を比較し、candidate が current より新しいか判定する
    static func isNewer(candidate rawCandidate: String, than rawCurrent: String) -> Bool {
        let candidateParts = parseComponents(rawCandidate)
        let currentParts = parseComponents(rawCurrent)
        let maxCount = max(candidateParts.count, currentParts.count)

        for i in 0..<maxCount {
            let candVal = i < candidateParts.count ? candidateParts[i] : 0
            let currVal = i < currentParts.count ? currentParts[i] : 0
            if candVal != currVal {
                return candVal > currVal
            }
        }
        return false
    }

    static func parseComponents(_ version: String) -> [Int] {
        let cleaned = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        let mainPart = cleaned.components(separatedBy: "-").first ?? cleaned
        return mainPart
            .components(separatedBy: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

@MainActor
final class SoftwareUpdaterManager: ObservableObject {
    static let shared = SoftwareUpdaterManager()

    let githubRepository: String
    let feedURLString: String
    let currentVersionString: String
    let currentBuildString: String
    let hasSparklePublicKey: Bool

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: "zenith.automaticallyChecksForUpdates")
            #if canImport(Sparkle)
            if hasSparklePublicKey {
                updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
            #endif
        }
    }

    @Published private(set) var isCheckingForUpdates: Bool = false
    @Published var statusMessage: String?
    @Published var latestReleaseURL: URL?

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        self.githubRepository = (info["GitHubRepository"] as? String) ?? "hareruya-maro/zen-ith"
        self.feedURLString = (info["SUFeedURL"] as? String)
            ?? "https://github.com/hareruya-maro/zen-ith/releases/latest/download/appcast.xml"
        self.currentVersionString = (info["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        self.currentBuildString = (info["CFBundleVersion"] as? String) ?? "1"

        let pubKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.hasSparklePublicKey = !pubKey.isEmpty

        let savedAutoCheck = UserDefaults.standard.object(forKey: "zenith.automaticallyChecksForUpdates") as? Bool ?? true
        self.automaticallyChecksForUpdates = savedAutoCheck

        #if canImport(Sparkle)
        let controller = SPUStandardUpdaterController(
            startingUpdater: hasSparklePublicKey,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        if hasSparklePublicKey {
            controller.updater.automaticallyChecksForUpdates = savedAutoCheck
        }
        self.updaterController = controller
        #endif
    }

    var canCheckForUpdates: Bool {
        !isCheckingForUpdates
    }

    /// アップデートを手動確認する
    /// - `SUPublicEDKey` が設定済みの本番ビルドでは Sparkle 2 の標準アップデータUIを起動
    /// - 鍵未設定の開発中ビルドでは GitHub Releases API (`hareruya-maro/zen-ith`) を直接確認
    func checkForUpdates() {
        #if canImport(Sparkle)
        if hasSparklePublicKey, let controller = updaterController {
            statusMessage = "Sparkle 2 でアップデートを確認しています..."
            controller.checkForUpdates(nil)
            return
        }
        #endif

        Task {
            await checkGitHubReleasesDirectly()
        }
    }

    func openGitHubReleasesPage() {
        let urlStr = "https://github.com/\(githubRepository)/releases"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkGitHubReleasesDirectly() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        statusMessage = "GitHub Releases (\(githubRepository)) を確認中..."
        latestReleaseURL = nil

        defer {
            isCheckingForUpdates = false
        }

        guard let apiURL = URL(string: "https://api.github.com/repos/\(githubRepository)/releases/latest") else {
            statusMessage = "⚠️ リリース確認URLが不正です"
            return
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                statusMessage = "⚠️ サーバー応答を取得できませんでした"
                return
            }

            if http.statusCode == 404 {
                statusMessage = "ℹ️ GitHub (\(githubRepository)) に公開リリースがまだありません（現在 v\(currentVersionString)）"
                return
            }

            guard (200...299).contains(http.statusCode) else {
                statusMessage = "⚠️ GitHub API エラー (HTTP \(http.statusCode))"
                return
            }

            let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
            if VersionComparator.isNewer(candidate: release.tagName, than: currentVersionString) {
                statusMessage = "🎉 新しいバージョン \(release.tagName) が利用可能です！"
                latestReleaseURL = URL(string: release.htmlUrl)
            } else {
                statusMessage = "✅ 最新バージョン（v\(currentVersionString)）を使用中です"
            }
        } catch {
            statusMessage = "⚠️ 通信エラー: \(error.localizedDescription)"
        }
    }
}

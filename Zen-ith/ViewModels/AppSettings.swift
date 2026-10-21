import Combine
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("zenith.deletionMode") var deletionModeRawValue: String = DeletionMode.hybrid.rawValue
    @AppStorage("zenith.scanDownloadsFolder") var scanDownloadsFolder: Bool = true
    @AppStorage("zenith.scanDesktopFolder") var scanDesktopFolder: Bool = false
    @AppStorage("zenith.showSizeInMenuBar") var showSizeInMenuBar: Bool = false
    @AppStorage("zenith.lastNonZeroAlertThresholdGB") var lastNonZeroAlertThresholdGB: Int = 50
    @AppStorage("zenith.alertThresholdGB") var alertThresholdGB: Int = 50 {
        didSet {
            if alertThresholdGB > 0 {
                lastNonZeroAlertThresholdGB = alertThresholdGB
                NotificationAndLaunchService.requestNotificationPermissionIfNeeded()
            }
        }
    }

    // Phase 2: ワークスペース探索 ＆ Docker設定
    @AppStorage("zenith.workspacePathsJSON") private var workspacePathsJSON: String = ""
    @AppStorage("zenith.hasInitializedWorkspaces") private var hasInitializedWorkspaces: Bool = false
    @AppStorage("zenith.scanWorkspaceRustMavenTarget") var scanWorkspaceRustMavenTarget: Bool = true
    @AppStorage("zenith.scanWorkspaceBuildGradleDirs") var scanWorkspaceBuildGradleDirs: Bool = true
    @AppStorage("zenith.enableDockerScan") var enableDockerScan: Bool = true

    // Phase 3: 定期スキャン設定 ＆ ログイン時自動起動
    @AppStorage("zenith.scanScheduleInterval") var scanScheduleIntervalRaw: Int = ScanScheduleInterval.every6Hours.rawValue
    @Published private(set) var launchAtLogin: Bool = false
    @Published var launchAtLoginError: String?

    // AIアドバイザー設定
    @AppStorage("zenith.aiProvider") var aiProviderRaw: String = AIProviderOption.auto.rawValue
    @AppStorage("zenith.localCLITool") var localCLIToolRaw: String = LocalCLITool.antigravity.rawValue
    @AppStorage("zenith.ollamaModel") var ollamaModel: String = ""
    @AppStorage("zenith.geminiAPIKey") var geminiAPIKey: String = ""
    @AppStorage("zenith.openAIAPIKey") var openAIAPIKey: String = ""

    init() {
        if !hasInitializedWorkspaces {
            let defaults = Self.detectDefaultWorkspacePaths()
            saveWorkspacePaths(defaults)
            hasInitializedWorkspaces = true
        }
        self.launchAtLogin = NotificationAndLaunchService.isLaunchAtLoginEnabled()
        if alertThresholdGB > 0 {
            NotificationAndLaunchService.requestNotificationPermissionIfNeeded()
        }
    }

    var deletionMode: DeletionMode {
        get { DeletionMode(rawValue: deletionModeRawValue) ?? .hybrid }
        set {
            deletionModeRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var scanScheduleInterval: ScanScheduleInterval {
        get { ScanScheduleInterval(rawValue: scanScheduleIntervalRaw) ?? .every6Hours }
        set {
            scanScheduleIntervalRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var aiProvider: AIProviderOption {
        get { AIProviderOption(rawValue: aiProviderRaw) ?? .auto }
        set {
            aiProviderRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var localCLITool: LocalCLITool {
        get { LocalCLITool(rawValue: localCLIToolRaw) ?? .antigravity }
        set {
            localCLIToolRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try NotificationAndLaunchService.setLaunchAtLogin(enabled: enabled)
            launchAtLogin = NotificationAndLaunchService.isLaunchAtLoginEnabled()
        } catch {
            launchAtLogin = NotificationAndLaunchService.isLaunchAtLoginEnabled()
            launchAtLoginError = "ログイン項目の変更に失敗しました（アプリケーションフォルダ配下での実行が必要な場合があります）"
        }
    }

    var workspacePaths: [String] {
        guard let data = workspacePathsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    var workspaceDirectories: [URL] {
        workspacePaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var workspaceScanOptions: WorkspaceScanOptions {
        WorkspaceScanOptions(
            includeRustMavenTarget: scanWorkspaceRustMavenTarget,
            includeBuildGradleDirs: scanWorkspaceBuildGradleDirs
        )
    }

    func addWorkspaceDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL.path
        var current = workspacePaths
        guard !current.contains(standardized) else { return }
        current.append(standardized)
        saveWorkspacePaths(current)
        objectWillChange.send()
    }

    func removeWorkspacePath(_ path: String) {
        var current = workspacePaths
        current.removeAll { $0 == path }
        saveWorkspacePaths(current)
        objectWillChange.send()
    }

    private func saveWorkspacePaths(_ paths: [String]) {
        if let data = try? JSONEncoder().encode(paths),
           let json = String(data: data, encoding: .utf8) {
            workspacePathsJSON = json
        }
    }

    private static func detectDefaultWorkspacePaths() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = ["Projects", "workspace", "dev", "Developer", "repos"]
        var found: [String] = []

        for folder in candidates {
            let url = home.appendingPathComponent(folder, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                found.append(url.standardizedFileURL.path)
            }
        }
        return found
    }

    var targetDownloadDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = []
        if scanDownloadsFolder {
            urls.append(home.appendingPathComponent("Downloads", isDirectory: true))
        }
        if scanDesktopFolder {
            urls.append(home.appendingPathComponent("Desktop", isDirectory: true))
        }
        return urls
    }
}

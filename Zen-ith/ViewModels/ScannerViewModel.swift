import AppKit
import Combine
import Foundation
import SwiftUI

struct CategoryGroup: Identifiable {
    let category: ScanCategoryType
    let items: [ScanItem]
    let totalBytes: Int64
    let selectedBytes: Int64
    let selectedCount: Int

    var id: String { category.id }

    /// 要注意でない項目のうち、すべて選択されているか
    var isCategoryChecked: Bool {
        let selectable = items.filter { !$0.isCaution }
        if selectable.isEmpty {
            return items.allSatisfy(\.isSelected) && !items.isEmpty
        }
        return selectable.allSatisfy(\.isSelected)
    }

    var isPartiallyChecked: Bool {
        selectedCount > 0 && !isCategoryChecked
    }
}

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published private(set) var items: [ScanItem] = []
    @Published private(set) var dockerDiskInfos: [DockerDiskInfo] = []
    @Published private(set) var diskSpace: DiskSpaceMetrics = DirectorySizeCalculator.currentDiskSpaceMetrics()
    @Published var selectedPreset: SmartFilterPreset = .recommended
    @Published var searchQuery: String = ""
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isCleaning: Bool = false
    @Published private(set) var cleanupProgressFraction: Double = 0
    @Published private(set) var cleanupProgressText: String = ""
    @Published private(set) var lastScanDate: Date?
    @Published var bannerMessage: String?
    @Published var expandedCategories: Set<ScanCategoryType> = Set(ScanCategoryType.allCases)
    @Published var showingSettings: Bool = false

    // AIアドバイザー状態
    @Published var activeAIItemID: String?
    @Published private(set) var itemAnalyses: [String: AIItemAnalysis] = [:]
    @Published private(set) var itemChatHistories: [String: [AIChatMessage]] = [:]
    @Published var aiQuestionDraft: String = ""
    @Published private(set) var isAskingAI: Bool = false

    let settings: AppSettings
    private var scanTask: Task<Void, Never>?
    private var periodicScanTask: Task<Void, Never>?
    private var lastAlertNotifiedDate: Date?

    init(settings: AppSettings) {
        self.settings = settings
        self.diskSpace = DirectorySizeCalculator.currentDiskSpaceMetrics()
        startScan()
        reschedulePeriodicScan()
    }

    var totalReclaimableBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedItems: [ScanItem] {
        items.filter(\.isSelected)
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedCount: Int {
        selectedItems.count
    }

    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filteredItems: [ScanItem] {
        guard isSearchActive else { return items }
        return items.filter { $0.matchesSearchQuery(searchQuery) }
    }

    var isOverAlertThreshold: Bool {
        guard settings.alertThresholdGB > 0 else { return false }
        let thresholdBytes = Int64(settings.alertThresholdGB) * 1_000_000_000
        return totalReclaimableBytes >= thresholdBytes
    }

    /// カテゴリごとにサイズ降順でグループ化（検索キーワード適用済み）
    var categoryGroups: [CategoryGroup] {
        let grouped = Dictionary(grouping: filteredItems, by: \.category)
        var result: [CategoryGroup] = []
        let showDockerDisk = !isSearchActive || "docker".localizedStandardContains(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))

        for category in ScanCategoryType.allCases {
            let categoryItems = grouped[category] ?? []
            if categoryItems.isEmpty && !(category == .docker && !dockerDiskInfos.isEmpty && showDockerDisk) {
                continue
            }
            let sortedItems = categoryItems.sorted { $0.sizeBytes > $1.sizeBytes }
            let total = sortedItems.reduce(0) { $0 + $1.sizeBytes }
            let selected = sortedItems.filter(\.isSelected)
            let selBytes = selected.reduce(0) { $0 + $1.sizeBytes }

            result.append(
                CategoryGroup(
                    category: category,
                    items: sortedItems,
                    totalBytes: total,
                    selectedBytes: selBytes,
                    selectedCount: selected.count
                )
            )
        }

        return result.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - AIアドバイザー操作

    func toggleAIAdvisor(for item: ScanItem) {
        if activeAIItemID == item.id {
            activeAIItemID = nil
        } else {
            activeAIItemID = item.id
            aiQuestionDraft = ""
            if itemAnalyses[item.id] == nil {
                itemAnalyses[item.id] = AIAdvisorService.generateInstantAnalysis(for: item)
            }
        }
    }

    func askAIQuestion(for item: ScanItem, presetQuestion: String? = nil) {
        let questionText = (presetQuestion ?? aiQuestionDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !questionText.isEmpty, !isAskingAI else { return }

        if presetQuestion == nil {
            aiQuestionDraft = ""
        }

        let userMsg = AIChatMessage(isUser: true, text: questionText)
        itemChatHistories[item.id, default: []].append(userMsg)
        isAskingAI = true

        let provider = settings.aiProvider
        let localCLI = settings.localCLITool
        let ollamaModel = settings.ollamaModel
        let geminiKey = settings.geminiAPIKey

        Task {
            let responseMsg = await AIAdvisorService.askAdvisor(
                item: item,
                question: questionText,
                provider: provider,
                localCLI: localCLI,
                ollamaModel: ollamaModel,
                geminiAPIKey: geminiKey
            )
            self.itemChatHistories[item.id, default: []].append(responseMsg)
            self.isAskingAI = false
        }
    }

    // MARK: - スキャン・クリーンアップ操作

    /// 定期スキャンタイマーを再構成する
    func reschedulePeriodicScan() {
        periodicScanTask?.cancel()
        guard let intervalSeconds = settings.scanScheduleInterval.timeIntervalSeconds else {
            periodicScanTask = nil
            return
        }

        periodicScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                if Task.isCancelled { break }
                guard let self else { break }
                if !self.isScanning && !self.isCleaning {
                    self.startScan(isBackgroundScheduled: true)
                }
            }
        }
    }

    func startScan(isBackgroundScheduled: Bool = false) {
        scanTask?.cancel()
        isScanning = true
        if !isBackgroundScheduled {
            bannerMessage = nil
        }

        let downloadDirs = settings.targetDownloadDirectories
        let workspaceDirs = settings.workspaceDirectories
        let workspaceOpts = settings.workspaceScanOptions
        let shouldScanDocker = settings.enableDockerScan
        let activePreset = selectedPreset

        scanTask = Task {
            async let globalItemsTask = GlobalCacheScanner.scanAll()
            async let downloadItemsTask = DownloadsSmartScanner.scanDirectories(downloadDirs)
            async let workspaceItemsTask = WorkspaceDeepScanner.scanWorkspaces(
                rootDirectories: workspaceDirs,
                options: workspaceOpts
            )
            async let dockerResultTask: DockerScanResult = shouldScanDocker
                ? await DockerScanner.scanDockerEnvironment()
                : DockerScanResult(items: [], diskInfos: [], isDaemonRunning: false)

            let (fetchedGlobal, fetchedDownloads, fetchedWorkspace, dockerResult) = await (
                globalItemsTask,
                downloadItemsTask,
                workspaceItemsTask,
                dockerResultTask
            )
            if Task.isCancelled { return }

            let now = Date()
            var combined = fetchedDownloads + fetchedWorkspace + dockerResult.items + fetchedGlobal
            combined.sort { $0.sizeBytes > $1.sizeBytes }

            for index in combined.indices {
                combined[index].isSelected = combined[index].matchesFilter(activePreset, now: now)
            }

            self.items = combined
            self.dockerDiskInfos = dockerResult.diskInfos
            self.diskSpace = DirectorySizeCalculator.currentDiskSpaceMetrics()
            self.lastScanDate = now
            self.isScanning = false

            self.evaluateCapacityAlertNotification(now: now)
        }
    }

    private func evaluateCapacityAlertNotification(now: Date) {
        let total = totalReclaimableBytes
        let thresholdGB = settings.alertThresholdGB

        if !isOverAlertThreshold {
            lastAlertNotifiedDate = nil
            return
        }

        if NotificationAndLaunchService.shouldSendCapacityAlert(
            totalBytes: total,
            thresholdGB: thresholdGB,
            lastNotifiedDate: lastAlertNotifiedDate,
            now: now
        ) {
            lastAlertNotifiedDate = now
            let topCategory = categoryGroups.first?.category.title
            NotificationAndLaunchService.sendCapacityAlertNotification(
                totalBytes: total,
                thresholdGB: thresholdGB,
                topCategoryTitle: topCategory
            )
        }
    }

    func applySmartFilter(_ preset: SmartFilterPreset) {
        selectedPreset = preset
        let now = Date()
        for index in items.indices {
            items[index].isSelected = items[index].matchesFilter(preset, now: now)
        }
    }

    func toggleItemSelection(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isSelected.toggle()
    }

    func toggleCategorySelection(_ category: ScanCategoryType) {
        guard let group = categoryGroups.first(where: { $0.category == category }) else {
            return
        }
        let targetState = !group.isCategoryChecked
        let visibleIDs = Set(group.items.map(\.id))

        for index in items.indices where visibleIDs.contains(items[index].id) {
            if targetState && items[index].isCaution {
                continue
            }
            items[index].isSelected = targetState
        }
    }

    func revealInFinder(_ item: ScanItem) {
        guard item.isFileSystemItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func revealURLInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func cleanSingleItem(_ item: ScanItem) {
        guard !isCleaning else { return }
        performItemsCleanup(targets: [item], singleItemName: item.name)
    }

    func cleanSelectedItems() {
        let targets = selectedItems
        guard !targets.isEmpty, !isCleaning else { return }
        performItemsCleanup(targets: targets, singleItemName: nil)
    }

    private func performItemsCleanup(targets: [ScanItem], singleItemName: String?) {
        isCleaning = true
        cleanupProgressFraction = 0
        cleanupProgressText = "クリーンアップ準備中..."
        bannerMessage = nil

        let mode = settings.deletionMode
        let preset = selectedPreset

        Task {
            let summary = await CleanupService.performCleanup(
                items: targets,
                deletionMode: mode,
                activePreset: preset
            ) { [weak self] current, total, itemName in
                await MainActor.run {
                    guard let self else { return }
                    self.cleanupProgressFraction = Double(current) / Double(max(1, total))
                    self.cleanupProgressText = "クリーンアップ中 (\(current)/\(total)): \(itemName)"
                }
            }

            if let activeID = self.activeAIItemID, summary.deletedItemIDs.contains(activeID) {
                self.activeAIItemID = nil
            }
            self.items.removeAll { summary.deletedItemIDs.contains($0.id) }
            self.diskSpace = DirectorySizeCalculator.currentDiskSpaceMetrics()
            self.isCleaning = false
            self.cleanupProgressFraction = 0
            self.cleanupProgressText = ""

            if !self.isOverAlertThreshold {
                self.lastAlertNotifiedDate = nil
            }

            let freedStr = ByteFormatter.string(fromBytes: summary.freedBytes)
            if summary.failedItems.isEmpty {
                if let singleName = singleItemName {
                    self.bannerMessage = "✅ \(singleName)（\(freedStr)）をクリーンアップしました"
                } else {
                    self.bannerMessage = "✅ \(freedStr)（\(summary.deletedItemIDs.count)項目）をクリーンアップしました"
                }
            } else {
                self.bannerMessage = "⚠️ \(freedStr) 完了（\(summary.failedItems.count)項目はスキップされました）"
            }
        }
    }
}

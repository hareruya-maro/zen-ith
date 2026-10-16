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
    @Published var selectedPreset: SmartFilterPreset = .recommended
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isCleaning: Bool = false
    @Published private(set) var cleanupProgressFraction: Double = 0
    @Published private(set) var cleanupProgressText: String = ""
    @Published private(set) var lastScanDate: Date?
    @Published var bannerMessage: String?
    @Published var expandedCategories: Set<ScanCategoryType> = Set(ScanCategoryType.allCases)

    let settings: AppSettings
    private var scanTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        startScan()
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

    var isOverAlertThreshold: Bool {
        guard settings.alertThresholdGB > 0 else { return false }
        let thresholdBytes = Int64(settings.alertThresholdGB) * 1_000_000_000
        return totalReclaimableBytes >= thresholdBytes
    }

    /// カテゴリごとにサイズ降順でグループ化
    var categoryGroups: [CategoryGroup] {
        let grouped = Dictionary(grouping: items, by: \.category)
        var result: [CategoryGroup] = []

        for category in ScanCategoryType.allCases {
            guard let categoryItems = grouped[category], !categoryItems.isEmpty else {
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

        // 容量の大きいカテゴリ順（降順）でソート
        return result.sorted { $0.totalBytes > $1.totalBytes }
    }

    func startScan() {
        scanTask?.cancel()
        isScanning = true
        bannerMessage = nil

        let downloadDirs = settings.targetDownloadDirectories
        let activePreset = selectedPreset

        scanTask = Task {
            async let globalItems = GlobalCacheScanner.scanAll()
            async let downloadItems = DownloadsSmartScanner.scanDirectories(downloadDirs)

            let (fetchedGlobal, fetchedDownloads) = await (globalItems, downloadItems)
            if Task.isCancelled { return }

            let now = Date()
            var combined = fetchedDownloads + fetchedGlobal
            combined.sort { $0.sizeBytes > $1.sizeBytes }

            for index in combined.indices {
                combined[index].isSelected = combined[index].matchesFilter(activePreset, now: now)
            }

            self.items = combined
            self.lastScanDate = now
            self.isScanning = false
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

        for index in items.indices where items[index].category == category {
            // 要注意項目は一括ONの時は保護し、一括OFFの時は一緒に解除する
            if targetState && items[index].isCaution {
                continue
            }
            items[index].isSelected = targetState
        }
    }

    func revealInFinder(_ item: ScanItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func cleanSelectedItems() {
        let targets = selectedItems
        guard !targets.isEmpty, !isCleaning else { return }

        isCleaning = true
        cleanupProgressFraction = 0
        cleanupProgressText = "クリーンアップ準備中..."
        bannerMessage = nil

        let mode = settings.deletionMode

        Task {
            let summary = await CleanupService.performCleanup(
                items: targets,
                deletionMode: mode
            ) { [weak self] current, total, itemName in
                await MainActor.run {
                    guard let self else { return }
                    self.cleanupProgressFraction = Double(current) / Double(max(1, total))
                    self.cleanupProgressText = "削除中 (\(current)/\(total)): \(itemName)"
                }
            }

            self.items.removeAll { summary.deletedItemIDs.contains($0.id) }
            self.isCleaning = false
            self.cleanupProgressFraction = 0
            self.cleanupProgressText = ""

            let freedStr = ByteFormatter.string(fromBytes: summary.freedBytes)
            if summary.failedItems.isEmpty {
                self.bannerMessage = "✅ \(freedStr)（\(summary.deletedItemIDs.count)項目）をクリーンアップしました"
            } else {
                self.bannerMessage = "⚠️ \(freedStr) 削除完了（\(summary.failedItems.count)項目は権限または使用中のためスキップ）"
            }
        }
    }
}

import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings
    @State private var showingSettings: Bool = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(
                    settings: settings,
                    onBack: { showingSettings = false },
                    onSettingsChanged: { viewModel.startScan() }
                )
            } else {
                scannerMainContent
            }
        }
        .frame(width: 420, height: 560)
    }

    private var scannerMainContent: some View {
        VStack(spacing: 0) {
            HeaderView(
                viewModel: viewModel,
                onOpenSettings: { showingSettings = true }
            )

            SmartFilterBarView(viewModel: viewModel)

            Divider()

            if viewModel.isScanning && viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("キャッシュと不要ファイルをスキャンしています...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.categoryGroups.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text("クリーンな状態です！")
                        .font(.headline)
                    Text("削除可能なキャッシュや不要ファイルは見つかりませんでした。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.categoryGroups) { group in
                            CategorySectionView(
                                group: group,
                                isExpanded: Binding(
                                    get: { viewModel.expandedCategories.contains(group.category) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            viewModel.expandedCategories.insert(group.category)
                                        } else {
                                            viewModel.expandedCategories.remove(group.category)
                                        }
                                    }
                                ),
                                onToggleCategory: {
                                    viewModel.toggleCategorySelection(group.category)
                                },
                                onToggleItem: { itemID in
                                    viewModel.toggleItemSelection(id: itemID)
                                },
                                onRevealItem: { item in
                                    viewModel.revealInFinder(item)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            Divider()

            FooterActionBarView(viewModel: viewModel)
        }
    }
}

import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if viewModel.showingSettings {
                SettingsView(
                    settings: settings,
                    onBack: { viewModel.showingSettings = false },
                    onSettingsChanged: { viewModel.startScan() },
                    onScheduleChanged: { viewModel.reschedulePeriodicScan() }
                )
            } else {
                scannerMainContent
            }
        }
        .frame(width: 520, height: 600)
    }

    private var scannerMainContent: some View {
        VStack(spacing: 0) {
            HeaderView(
                viewModel: viewModel,
                onOpenSettings: { viewModel.showingSettings = true }
            )

            SmartFilterBarView(viewModel: viewModel)

            Divider()

            if viewModel.isScanning && viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("キャッシュ・ワークスペース・Docker環境を走査中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.categoryGroups.isEmpty {
                if viewModel.isSearchActive {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("「\(viewModel.searchQuery)」に一致する項目はありません")
                            .font(.headline)
                        Button("検索をクリア") {
                            viewModel.searchQuery = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
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
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.categoryGroups) { group in
                            CategorySectionView(
                                group: group,
                                dockerDiskInfos: group.category == .docker ? viewModel.dockerDiskInfos : [],
                                viewModel: viewModel,
                                isExpanded: Binding(
                                    get: { viewModel.expandedCategories.contains(group.category) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            viewModel.expandedCategories.insert(group.category)
                                        } else {
                                            viewModel.expandedCategories.remove(group.category)
                                        }
                                    }
                                )
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

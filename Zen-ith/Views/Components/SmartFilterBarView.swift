import SwiftUI

struct SmartFilterBarView: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        VStack(spacing: 6) {
            Picker("スマートフィルタ", selection: Binding(
                get: { viewModel.selectedPreset },
                set: { viewModel.applySmartFilter($0) }
            )) {
                ForEach(SmartFilterPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(viewModel.isScanning || viewModel.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

import SwiftUI

@main
struct ZenIthApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var scannerViewModel: ScannerViewModel

    init() {
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        _scannerViewModel = StateObject(wrappedValue: ScannerViewModel(settings: appSettings))
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView(
                viewModel: scannerViewModel,
                settings: settings
            )
        } label: {
            MenuBarLabelView(
                viewModel: scannerViewModel,
                settings: settings
            )
        }
        .menuBarExtraStyle(.window)
    }
}

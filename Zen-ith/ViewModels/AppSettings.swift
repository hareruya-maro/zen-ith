import Combine
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("zenith.deletionMode") var deletionModeRawValue: String = DeletionMode.hybrid.rawValue
    @AppStorage("zenith.scanDownloadsFolder") var scanDownloadsFolder: Bool = true
    @AppStorage("zenith.scanDesktopFolder") var scanDesktopFolder: Bool = false
    @AppStorage("zenith.showSizeInMenuBar") var showSizeInMenuBar: Bool = true
    @AppStorage("zenith.alertThresholdGB") var alertThresholdGB: Int = 50

    var deletionMode: DeletionMode {
        get { DeletionMode(rawValue: deletionModeRawValue) ?? .hybrid }
        set {
            deletionModeRawValue = newValue.rawValue
            objectWillChange.send()
        }
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

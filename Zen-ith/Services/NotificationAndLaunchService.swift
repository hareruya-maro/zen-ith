import Foundation
import ServiceManagement
import UserNotifications

nonisolated enum NotificationAndLaunchService {
    /// クールダウン時間（同一閾値超過の重複通知を6時間抑止）
    static let defaultAlertCooldownSeconds: TimeInterval = 6 * 3_600

    // MARK: - ログイン時自動起動 (SMAppService.mainApp)

    static func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    // MARK: - 容量アラート通知判定と通知センター送信

    /// 容量アラート通知を送るべきかを判定する純粋関数（単体テスト可能）
    static func shouldSendCapacityAlert(
        totalBytes: Int64,
        thresholdGB: Int,
        lastNotifiedDate: Date?,
        now: Date = Date(),
        cooldownSeconds: TimeInterval = defaultAlertCooldownSeconds
    ) -> Bool {
        guard thresholdGB > 0 else { return false }
        let thresholdBytes = Int64(thresholdGB) * 1_000_000_000
        guard totalBytes >= thresholdBytes else { return false }

        if let lastNotifiedDate {
            let elapsed = now.timeIntervalSince(lastNotifiedDate)
            if elapsed < cooldownSeconds {
                return false
            }
        }
        return true
    }

    static func requestNotificationPermissionIfNeeded() {
        guard isRunningInAppBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendCapacityAlertNotification(
        totalBytes: Int64,
        thresholdGB: Int,
        topCategoryTitle: String?
    ) {
        guard isRunningInAppBundle else { return }
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        enqueueAlertNotification(
                            center: center,
                            totalBytes: totalBytes,
                            thresholdGB: thresholdGB,
                            topCategoryTitle: topCategoryTitle
                        )
                    }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                enqueueAlertNotification(
                    center: center,
                    totalBytes: totalBytes,
                    thresholdGB: thresholdGB,
                    topCategoryTitle: topCategoryTitle
                )
            }
        }
    }

    private static func enqueueAlertNotification(
        center: UNUserNotificationCenter,
        totalBytes: Int64,
        thresholdGB: Int,
        topCategoryTitle: String?
    ) {
        let formattedTotal = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let content = UNMutableNotificationContent()
        content.title = "🧹 開発キャッシュが \(formattedTotal) に達しています"
        if let topCategoryTitle {
            content.body = "設定されたアラート閾値（\(thresholdGB) GB）を超過しました。最大カテゴリ「\(topCategoryTitle)」などをメニューバーから整理できます。"
        } else {
            content.body = "設定されたアラート閾値（\(thresholdGB) GB）を超過しました。メニューバーの Zen-ith からワンクリックで整理できます。"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "dev.zenith.cleaner.capacity-alert",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private static var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

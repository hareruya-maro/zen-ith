import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: SoftwareUpdaterManager = .shared
    let onBack: () -> Void
    let onSettingsChanged: () -> Void
    let onScheduleChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ナビゲーションヘッダー
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Zen-ith 設定")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // AIアドバイザー設定（ハイブリッド / ローカルCLI / Ollama / Gemini API）
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI解説・質問アドバイザー設定", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold))

                        Picker("AIエンジン方式", selection: Binding(
                            get: { settings.aiProvider },
                            set: { settings.aiProvider = $0 }
                        )) {
                            ForEach(AIProviderOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .font(.system(size: 12))

                        Text(settings.aiProvider.description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if settings.aiProvider == .localCLI || settings.aiProvider == .auto {
                            HStack {
                                Text("優先するローカルCLI")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("ローカルCLI", selection: Binding(
                                    get: { settings.localCLITool },
                                    set: { settings.localCLITool = $0 }
                                )) {
                                    ForEach(LocalCLITool.allCases) { tool in
                                        Text(tool.displayName).tag(tool)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 230)
                            }
                        }

                        if settings.aiProvider == .ollama || settings.aiProvider == .auto {
                            HStack {
                                Text("Ollama モデル名 (空欄で自動検出)")
                                    .font(.system(size: 11))
                                Spacer()
                                TextField("例: qwen2.5-coder, llama3.2", text: $settings.ollamaModel)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                                    .frame(width: 190)
                            }
                        }

                        if settings.aiProvider == .geminiAPI || settings.aiProvider == .auto {
                            HStack {
                                Text("Gemini API キー (任意)")
                                    .font(.system(size: 11))
                                Spacer()
                                SecureField("AIzaSy... (環境変数 GEMINI_API_KEY も可)", text: $settings.geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                                    .frame(width: 230)
                            }
                        }

                        if settings.aiProvider == .openAIAPI || settings.aiProvider == .auto {
                            HStack {
                                Text("OpenAI API キー (任意)")
                                    .font(.system(size: 11))
                                Spacer()
                                SecureField("sk-... (環境変数 OPENAI_API_KEY も可)", text: $settings.openAIAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                                    .frame(width: 230)
                            }
                        }
                    }

                    Divider()

                    // ワークスペース深層スキャン管理
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("ワークスペース管理 (node_modules等)", systemImage: "folder.fill.badge.gearshape")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button {
                                pickWorkspaceFolder()
                            } label: {
                                Label("追加", systemImage: "plus")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if settings.workspacePaths.isEmpty {
                            Text("登録されたワークスペースがありません。「追加」から ~/Projects 等の親フォルダを登録してください。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(settings.workspacePaths, id: \.self) { path in
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)

                                        Text(GlobalCacheScanner.abbreviateHomePath(path))
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        Spacer()

                                        Button {
                                            settings.removeWorkspacePath(path)
                                            onSettingsChanged()
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("このワークスペースを監視対象から外す")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                                }
                            }
                        }

                        Toggle("Rust / Maven の target フォルダを検出対象に含める", isOn: $settings.scanWorkspaceRustMavenTarget)
                            .font(.system(size: 11))
                            .onChange(of: settings.scanWorkspaceRustMavenTarget) { _, _ in
                                onSettingsChanged()
                            }

                        Toggle("Android / Java / C++ の build, .gradle, .cxx を含める", isOn: $settings.scanWorkspaceBuildGradleDirs)
                            .font(.system(size: 11))
                            .onChange(of: settings.scanWorkspaceBuildGradleDirs) { _, _ in
                                onSettingsChanged()
                            }
                    }

                    Divider()

                    // Docker / コンテナ連携
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Docker / コンテナ連携", systemImage: "shippingbox.fill")
                            .font(.system(size: 13, weight: .semibold))

                        Toggle("Docker CLI (docker system df) スキャンを有効にする", isOn: $settings.enableDockerScan)
                            .font(.system(size: 12))
                            .onChange(of: settings.enableDockerScan) { _, _ in
                                onSettingsChanged()
                            }
                    }

                    Divider()

                    // ダウンロード＆ローカル不要ファイル監視対象
                    VStack(alignment: .leading, spacing: 8) {
                        Label("スマート整理の対象フォルダ", systemImage: "tray.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .semibold))

                        Toggle("ダウンロード (~/Downloads)", isOn: $settings.scanDownloadsFolder)
                            .font(.system(size: 12))
                            .onChange(of: settings.scanDownloadsFolder) { _, _ in
                                onSettingsChanged()
                            }

                        Toggle("デスクトップ (~/Desktop)", isOn: $settings.scanDesktopFolder)
                            .font(.system(size: 12))
                            .onChange(of: settings.scanDesktopFolder) { _, _ in
                                onSettingsChanged()
                            }
                    }

                    Divider()

                    // 定期スキャン設定 ＆ 容量アラート通知
                    VStack(alignment: .leading, spacing: 10) {
                        Label("定期スキャン・容量アラート通知", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))

                        HStack {
                            Text("バックグラウンド定期スキャン")
                                .font(.system(size: 12))
                            Spacer()
                            Picker("定期スキャン", selection: Binding(
                                get: { settings.scanScheduleInterval },
                                set: { newValue in
                                    settings.scanScheduleInterval = newValue
                                    onScheduleChanged()
                                }
                            )) {
                                ForEach(ScanScheduleInterval.allCases) { interval in
                                    Text(interval.title).tag(interval)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        HStack {
                            Text("容量アラート通知（通知センター）")
                                .font(.system(size: 12))
                            Spacer()
                            Picker("容量アラート閾値", selection: $settings.alertThresholdGB) {
                                Text("OFF").tag(0)
                                Text("30 GB 超過時").tag(30)
                                Text("50 GB 超過時").tag(50)
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        Toggle("メニューバーに検出容量テキストを表示する", isOn: $settings.showSizeInMenuBar)
                            .font(.system(size: 12))
                    }

                    Divider()

                    // 削除方式
                    VStack(alignment: .leading, spacing: 8) {
                        Label("削除（クリーンアップ）方式", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))

                        ForEach(DeletionMode.allCases) { mode in
                            Button {
                                settings.deletionMode = mode
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
     
                                    Image(systemName: settings.deletionMode == mode ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(settings.deletionMode == mode ? Color.accentColor : Color.secondary)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text(mode.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(settings.deletionMode == mode ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    // システム設定（ログイン時自動起動）
                    VStack(alignment: .leading, spacing: 8) {
                        Label("システム設定", systemImage: "macwindow")
                            .font(.system(size: 13, weight: .semibold))

                        Toggle("Macログイン時に自動起動 (SMAppService)", isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { settings.updateLaunchAtLogin($0) }
                        ))
                        .font(.system(size: 12))

                        if let errorMsg = settings.launchAtLoginError {
                            Text(errorMsg)
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    Divider()

                    // ソフトウェアアップデート (Sparkle 2 / GitHub Releases)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("ソフトウェアアップデート (Sparkle 2)", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(updater.githubRepository)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Toggle("定期的に自動でアップデートを確認する", isOn: $updater.automaticallyChecksForUpdates)
                            .font(.system(size: 12))

                        HStack(spacing: 8) {
                            Button {
                                updater.checkForUpdates()
                            } label: {
                                HStack(spacing: 5) {
                                    if updater.isCheckingForUpdates {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    Text("今すぐアップデートを確認...")
                                }
                                .font(.system(size: 11.5, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!updater.canCheckForUpdates)

                            Button {
                                updater.openGitHubReleasesPage()
                            } label: {
                                Label("GitHub Releases", systemImage: "safari")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if let status = updater.statusMessage {
                            HStack(spacing: 6) {
                                Text(status)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                if let releaseURL = updater.latestReleaseURL {
                                    Button("ダウンロードページを開く") {
                                        NSWorkspace.shared.open(releaseURL)
                                    }
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // フッター：アプリ終了ボタン
            HStack {
                Text("Zen-ith v\(updater.currentVersionString) (Build \(updater.currentBuildString))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("アプリを終了", systemImage: "power")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func pickWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.title = "ワークスペースのルートフォルダを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                settings.addWorkspaceDirectory(url)
            }
            onSettingsChanged()
        }
    }
}

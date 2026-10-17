import Foundation

nonisolated struct DockerSystemDfRow: Decodable, Sendable {
    let type: String
    let totalCount: String
    let active: String
    let size: String
    let reclaimable: String

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case totalCount = "TotalCount"
        case active = "Active"
        case size = "Size"
        case reclaimable = "Reclaimable"
    }
}

nonisolated struct DockerScanResult: Sendable {
    let items: [ScanItem]
    let diskInfos: [DockerDiskInfo]
    let isDaemonRunning: Bool
}

nonisolated enum DockerScanner {
    @concurrent
    static func scanDockerEnvironment(
        homeDir: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> DockerScanResult {
        async let dfOutputTask = fetchDockerSystemDfJSONLines()
        async let diskInfosTask = detectVirtualDiskFiles(homeDir: homeDir)

        let (jsonLines, diskInfos) = await (dfOutputTask, diskInfosTask)

        guard let jsonLines, !jsonLines.isEmpty else {
            return DockerScanResult(
                items: [],
                diskInfos: diskInfos,
                isDaemonRunning: false
            )
        }

        let items = parseDockerSystemDfLines(jsonLines, homeDir: homeDir)
        return DockerScanResult(
            items: items,
            diskInfos: diskInfos,
            isDaemonRunning: true
        )
    }

    /// `docker system df --format '{{json .}}'` の出力行をパースして ScanItem 配列に変換する
    static func parseDockerSystemDfLines(
        _ lines: [String],
        homeDir: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ScanItem] {
        let decoder = JSONDecoder()
        var items: [ScanItem] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let row = try? decoder.decode(DockerSystemDfRow.self, from: data),
                  let resourceType = DockerResourceType(rawValue: row.type) else {
                continue
            }

            let reclaimableBytes = parseDockerSizeString(row.reclaimable)
            let totalBytes = parseDockerSizeString(row.size)

            // Local Volumes の場合は Reclaimable が 0 でも未使用ボリュームが存在しうるが、回収可能サイズが 0 ならスキップ
            let effectiveBytes = reclaimableBytes > 0 ? reclaimableBytes : (resourceType == .localVolumes ? totalBytes : 0)
            guard effectiveBytes > 0 else { continue }

            let virtualURL = homeDir.appendingPathComponent(".docker/zenith-\(resourceType.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
            let subtitle = "合計 \(row.totalCount)件 (稼働中: \(row.active)) • 回収可能: \(row.reclaimable)"

            items.append(
                ScanItem(
                    id: "docker:\(resourceType.rawValue)",
                    name: resourceType.displayName,
                    subtitle: subtitle,
                    url: virtualURL,
                    sizeBytes: effectiveBytes,
                    lastModified: Date(),
                    category: .docker,
                    targetKind: .dockerPrune(resourceType),
                    smartBadge: .dockerReclaimable(totalSizeLabel: row.size),
                    isCaution: resourceType.isCaution,
                    cautionReason: resourceType.cautionReason
                )
            )
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Docker CLIのサイズ表記（例: `"1.24GB (85%)"`, `"45.2MB"`, `"512kB"`, `"2.5GiB"`, `"0B"`）をバイト数に変換する
    static func parseDockerSizeString(_ raw: String) -> Int64 {
        // カッコ内のパーセンテージ表記 ` (85%)` を除去
        let mainPart = raw.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? raw
        guard !mainPart.isEmpty else { return 0 }

        let pattern = #"^([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: mainPart,
                  range: NSRange(mainPart.startIndex..<mainPart.endIndex, in: mainPart)
              ),
              let numberRange = Range(match.range(at: 1), in: mainPart),
              let unitRange = Range(match.range(at: 2), in: mainPart),
              let value = Double(mainPart[numberRange]) else {
            return 0
        }

        let unit = mainPart[unitRange].uppercased()
        let multiplier: Double = switch unit {
        case "B": 1
        case "KB": 1_000
        case "KIB": 1_024
        case "MB": 1_000_000
        case "MIB": 1_048_576
        case "GB": 1_000_000_000
        case "GIB": 1_073_741_824
        case "TB": 1_000_000_000_000
        case "TIB": 1_099_511_627_776
        default: 1
        }

        return Int64(value * multiplier)
    }

    /// Docker仮想ディスクファイル（Docker.raw / ~/.orbstack / ~/.colima）の実サイズを検出する
    @concurrent
    static func detectVirtualDiskFiles(
        homeDir: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> [DockerDiskInfo] {
        var infos: [DockerDiskInfo] = []

        // 1. Docker Desktop (Docker.raw)
        let dockerRawURL = homeDir.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        if let metrics = DirectorySizeCalculator.calculateMetrics(for: dockerRawURL) {
            infos.append(
                DockerDiskInfo(
                    providerName: "Docker Desktop (Docker.raw)",
                    diskURL: dockerRawURL,
                    allocatedBytes: metrics.sizeBytes,
                    hintText: "コンテナやイメージを削除してもMac本体の空き容量が増えない場合は、Docker Desktopの Settings > Resources > Virtual disk limit で上限を縮小するか、動的割り当てが軽量な OrbStack への移行を検討してください。"
                )
            )
        }

        // 2. OrbStack (~/.orbstack)
        let orbstackURL = homeDir.appendingPathComponent(".orbstack")
        if let metrics = DirectorySizeCalculator.calculateMetrics(for: orbstackURL) {
            infos.append(
                DockerDiskInfo(
                    providerName: "OrbStack (~/.orbstack)",
                    diskURL: orbstackURL,
                    allocatedBytes: metrics.sizeBytes,
                    hintText: "OrbStackの仮想ディスク使用量です。不要イメージやビルドキャッシュをPruneするとホスト側ストレージも自動的に解放されます。"
                )
            )
        }

        // 3. Colima (~/.colima)
        let colimaURL = homeDir.appendingPathComponent(".colima")
        if let metrics = DirectorySizeCalculator.calculateMetrics(for: colimaURL) {
            infos.append(
                DockerDiskInfo(
                    providerName: "Colima (~/.colima)",
                    diskURL: colimaURL,
                    allocatedBytes: metrics.sizeBytes,
                    hintText: "Colimaの仮想マシンディスク使用量です。"
                )
            )
        }

        return infos
    }

    /// `/bin/zsh -lc "docker system df --format '{{json .}}'"` をタイムアウト付きで実行する
    @concurrent
    private static func fetchDockerSystemDfJSONLines() async -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "docker system df --format '{{json .}}'"]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // タイムアウト監視（Dockerデーモン停止時にハングしないよう最大6秒で打ち切る）
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if process.isRunning {
                process.terminate()
            }
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutTask.cancel()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 指定された DockerResourceType に対して `docker ... prune` コマンドを実行する
    static func executeDockerPrune(
        resourceType: DockerResourceType,
        preset: SmartFilterPreset
    ) -> Result<Void, Error> {
        let args = resourceType.pruneArguments(for: preset)
        let cmdString = (["docker"] + args.map { arg in
            arg.contains("=") ? "'\(arg)'" : arg
        }).joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", cmdString]

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .success(())
            } else {
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "docker prune failed (exit \(process.terminationStatus))"
                return .failure(NSError(domain: "DockerScanner", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: errMsg
                ]))
            }
        } catch {
            return .failure(error)
        }
    }
}

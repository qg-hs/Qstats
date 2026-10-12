import AppKit
import Foundation

/// 远程发布资产模型
struct ReleaseAsset {
    let name: String
    let downloadURL: URL
    let size: Int64
}

/// 远程版本详情模型
struct RemoteRelease {
    let version: String
    let tagName: String
    let releaseNotes: String
    let releasePageURL: URL
    let matchedAsset: ReleaseAsset?
}

/// 下载进度与安装状态流转
enum UpdateProgressState {
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64, speedBytesPerSec: Double)
    case extractingAndInstalling
}

/// 自定义自更新异常定义
enum UpdateError: LocalizedError {
    case invalidResponse
    case assetNotFound(architecture: String)
    case downloadFailed(String)
    case mountFailed(String)
    case targetAppNotFound
    case scriptExecutionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "未能解析 GitHub Releases 响应数据。"
        case .assetNotFound(let arch):
            return "未在最新版本中找到适配当前架构（\(arch)）的 DMG 安装镜像。"
        case .downloadFailed(let reason):
            return "安装包下载失败：\(reason)"
        case .mountFailed(let reason):
            return "挂载安装镜像失败：\(reason)"
        case .targetAppNotFound:
            return "安装镜像中未找到有效的 Qstats.app 应用程序包。"
        case .scriptExecutionFailed(let reason):
            return "启动跨进程更新守护脚本失败：\(reason)"
        case .cancelled:
            return "用户已取消下载。"
        }
    }
}

/// 生产级原生应用自更新管理器（支持架构感知匹配、流式断点下载、静默解包与跨进程原子替换重启）
final class AppUpdateManager: NSObject, URLSessionDownloadDelegate {
    static let shared = AppUpdateManager()

    private let repoAPI = "https://api.github.com/repos/qg-hs/Qstats/releases/latest"
    private let fallbackURL = "https://raw.githubusercontent.com/qg-hs/Qstats/main/VERSION"

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var progressHandler: ((UpdateProgressState) -> Void)?
    private var completionHandler: ((Result<Void, Error>) -> Void)?

    private var lastBytesWritten: Int64 = 0
    private var lastSpeedCheckTime: CFAbsoluteTime = 0
    private var currentSpeed: Double = 0
    private var destinationDMGURL: URL?

    override private init() {
        super.init()
    }

    // MARK: - 架构判定与匹配逻辑

    /// 获取当前机器编译目标架构匹配关键字
    static var targetArchKeyword: String {
        #if arch(arm64)
        return "apple-silicon"
        #else
        return "intel"
        #endif
    }

    /// 提取并匹配最佳架构的 DMG 资产
    static func matchBestAsset(from assetsArray: [[String: Any]]) -> ReleaseAsset? {
        let keyword = targetArchKeyword
        var exactMatch: ReleaseAsset?
        var fallbackDMG: ReleaseAsset?

        for item in assetsArray {
            guard let name = item["name"] as? String,
                  let urlString = item["browser_download_url"] as? String,
                  let downloadURL = URL(string: urlString),
                  name.hasSuffix(".dmg") else {
                continue
            }
            let size = (item["size"] as? NSNumber)?.int64Value ?? 0
            let asset = ReleaseAsset(name: name, downloadURL: downloadURL, size: size)

            if name.localizedCaseInsensitiveContains(keyword) {
                exactMatch = asset
                break
            } else if fallbackDMG == nil {
                fallbackDMG = asset
            }
        }
        return exactMatch ?? fallbackDMG
    }

    /// 比较两版本号（如 "1.8.3" 是否大于 "1.8.2"）
    static func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return cleanRemote.compare(cleanCurrent, options: .numeric) == .orderedDescending
    }

    // MARK: - 1. 检查最新版本

    func checkForUpdates(completion: @escaping (Result<RemoteRelease?, Error>) -> Void) {
        guard let apiURL = URL(string: repoAPI) else {
            completion(.failure(UpdateError.invalidResponse))
            return
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Qstats-macOS-Updater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.fallbackCheck(completion: completion, originalError: error)
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                self?.fallbackCheck(completion: completion, originalError: UpdateError.invalidResponse)
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let body = json["body"] as? String ?? ""
            let htmlURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
                ?? URL(string: "https://github.com/qg-hs/Qstats/releases/latest")!
            let assets = json["assets"] as? [[String: Any]] ?? []
            let matchedAsset = Self.matchBestAsset(from: assets)

            let release = RemoteRelease(
                version: remoteVersion,
                tagName: tagName,
                releaseNotes: body,
                releasePageURL: htmlURL,
                matchedAsset: matchedAsset
            )
            completion(.success(release))
        }.resume()
    }

    /// 降级容灾：若 GitHub API 频控受限，读取 raw.githubusercontent.com 的 VERSION
    private func fallbackCheck(completion: @escaping (Result<RemoteRelease?, Error>) -> Void, originalError: Error) {
        guard let rawURL = URL(string: fallbackURL) else {
            completion(.failure(originalError))
            return
        }

        var rawReq = URLRequest(url: rawURL)
        rawReq.timeoutInterval = 6
        rawReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: rawReq) { data, _, _ in
            guard let data = data,
                  let rawStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawStr.isEmpty else {
                completion(.failure(originalError))
                return
            }

            let remoteVersion = rawStr.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let releasesURL = URL(string: "https://github.com/qg-hs/Qstats/releases/latest")!
            let fallbackRelease = RemoteRelease(
                version: remoteVersion,
                tagName: "v\(remoteVersion)",
                releaseNotes: "包含最新性能改进与缺陷修复。",
                releasePageURL: releasesURL,
                matchedAsset: nil
            )
            completion(.success(fallbackRelease))
        }.resume()
    }

    // MARK: - 2. 自动下载与进度回调

    func startDownload(
        asset: ReleaseAsset,
        onProgress: @escaping (UpdateProgressState) -> Void,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) {
        cancelDownload()

        self.progressHandler = onProgress
        self.completionHandler = onCompletion
        self.lastBytesWritten = 0
        self.lastSpeedCheckTime = CFAbsoluteTimeGetCurrent()
        self.currentSpeed = 0

        let tempDir = FileManager.default.temporaryDirectory
        let targetFileName = "QstatsUpdate-\(UUID().uuidString).dmg"
        self.destinationDMGURL = tempDir.appendingPathComponent(targetFileName)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session

        var request = URLRequest(url: asset.downloadURL)
        request.setValue("Qstats-macOS-Updater", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)
        self.downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        if let dest = destinationDMGURL {
            try? FileManager.default.removeItem(at: dest)
            destinationDMGURL = nil
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let timeDelta = now - lastSpeedCheckTime

        if timeDelta >= 0.3 {
            let bytesDelta = totalBytesWritten - lastBytesWritten
            currentSpeed = Double(bytesDelta) / timeDelta
            lastSpeedCheckTime = now
            lastBytesWritten = totalBytesWritten
        }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0

        progressHandler?(
            .downloading(
                progress: min(1.0, max(0.0, progress)),
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite,
                speedBytesPerSec: currentSpeed
            )
        )
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                completionHandler?(.failure(UpdateError.cancelled))
            } else {
                completionHandler?(.failure(UpdateError.downloadFailed(error.localizedDescription)))
            }
            cleanUpSession()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let dest = destinationDMGURL else {
            completionHandler?(.failure(UpdateError.downloadFailed("临时文件目标路径丢失")))
            cleanUpSession()
            return
        }

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)

            // 通知外部进入解包与安装阶段
            progressHandler?(.extractingAndInstalling)

            // 调度到后台队列执行挂载与自杀重启替换脚本
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try self?.performMountAndRelaunch(dmgPath: dest.path)
                    DispatchQueue.main.async {
                        self?.completionHandler?(.success(()))
                        self?.cleanUpSession()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.completionHandler?(.failure(error))
                        self?.cleanUpSession()
                    }
                }
            }
        } catch {
            completionHandler?(.failure(UpdateError.downloadFailed(error.localizedDescription)))
            cleanUpSession()
        }
    }

    private func cleanUpSession() {
        session?.finishTasksAndInvalidate()
        session = nil
        downloadTask = nil
    }

    // MARK: - 3. 静默挂载提取与原子替换重启

    /// 执行 DMG 挂载、脚本生成与独立外部进程拉起
    private func performMountAndRelaunch(dmgPath: String) throws {
        // 1. 确定当前运行的 App 束物理路径
        let currentAppBundle = Bundle.main.bundleURL.standardized.path
        guard currentAppBundle.hasSuffix(".app") else {
            throw UpdateError.targetAppNotFound
        }

        // 2. 创建临时独立挂载点
        let mountPoint = "/tmp/qstats_mount_\(ProcessInfo.processInfo.processIdentifier)_\(Int(Date().timeIntervalSince1970))"
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        // 3. 执行 hdiutil 静默只读挂载
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = ["attach", dmgPath, "-mountpoint", mountPoint, "-nobrowse", "-readonly", "-quiet"]
        try attachProcess.run()
        attachProcess.waitUntilExit()

        guard attachProcess.terminationStatus == 0 else {
            throw UpdateError.mountFailed("hdiutil attach 退出码: \(attachProcess.terminationStatus)")
        }

        // 4. 探查挂载卷中的 Qstats.app
        let candidateApp = "\(mountPoint)/Qstats.app"
        let sourceAppPath: String
        if fileManager.fileExists(atPath: candidateApp) {
            sourceAppPath = candidateApp
        } else {
            // 兜底探查挂载卷中的首个 .app
            let items = (try? fileManager.contentsOfDirectory(atPath: mountPoint)) ?? []
            guard let firstApp = items.first(where: { $0.hasSuffix(".app") }) else {
                // 卸载并清理
                let detachProcess = Process()
                detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detachProcess.arguments = ["detach", mountPoint, "-force", "-quiet"]
                try? detachProcess.run()
                detachProcess.waitUntilExit()
                try? fileManager.removeItem(atPath: mountPoint)
                throw UpdateError.targetAppNotFound
            }
            sourceAppPath = "\(mountPoint)/\(firstApp)"
        }

        // 5. 生成原子替换与自启动守护脚本（微型 POSIX Shell 独立执行）
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptPath = "/tmp/qstats_updater_\(pid).sh"
        let scriptContent = """
        #!/bin/sh
        OLD_PID=$1
        MOUNT_PT="$2"
        SRC_APP="$3"
        DST_APP="$4"
        DMG_FILE="$5"

        # 循环等待原进程完全释放退出（超时 10 秒硬保底）
        WAIT_COUNT=0
        while kill -0 "$OLD_PID" 2>/dev/null; do
            sleep 0.1
            WAIT_COUNT=$((WAIT_COUNT+1))
            if [ "$WAIT_COUNT" -gt 100 ]; then
                kill -9 "$OLD_PID" 2>/dev/null
                break
            fi
        done

        # 替换 App 束
        rm -rf "$DST_APP" 2>/dev/null
        cp -R "$SRC_APP" "$DST_APP"

        # 清除 Gatekeeper Quarantine 隔离标志，保证首次打开免拦截
        xattr -dr com.apple.quarantine "$DST_APP" 2>/dev/null || true

        # 强制卸载临时 DMG 并清除残留
        hdiutil detach "$MOUNT_PT" -force -quiet 2>/dev/null || true
        rm -rf "$MOUNT_PT" 2>/dev/null || true
        rm -f "$DMG_FILE" 2>/dev/null || true

        # 重新启动新版应用
        open "$DST_APP"

        # 脚本自删除
        rm -f "$0" 2>/dev/null || true
        """

        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", scriptPath]
        try chmodProcess.run()
        chmodProcess.waitUntilExit()

        // 6. 派发独立后台进程运行该脚本
        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        launchProcess.arguments = [
            scriptPath,
            "\(pid)",
            mountPoint,
            sourceAppPath,
            currentAppBundle,
            dmgPath
        ]
        try launchProcess.run()

        // 7. 稍作微秒级让度后，平滑退出当前旧进程，触发守护脚本接管覆盖并秒级拉起新版本
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
    }
}

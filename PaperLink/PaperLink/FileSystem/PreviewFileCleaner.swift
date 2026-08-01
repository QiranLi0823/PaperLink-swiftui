//
//  PreviewFileCleaner.swift
//  PaperLink
//
//  Sprint 9.17：清理 .paperlink-preview-*.html 临时文件。
//
//  背景：HTMLPreview 把 WKWebView 要加载的 HTML 写到 .pml 同目录（隐藏文件名带 hash 后缀），
//        正常情况下应用退出后这些临时文件就成了垃圾。需要：
//          1. 启动时扫 Bundle.resources（demo 文件可能写在 bundle 里）→ 删
//          2. 启动时扫描用户在 Open Recent 里最近打开的目录 → 删孤儿
//          3. 应用退出时（willTerminate）→ 删本次运行写入的全部文件
//          4. HTMLPreview updateNSView 切换 rootURL 时 → 扫新 rootURL 下的孤儿
//
//  设计：用单例 + Set<URL> 记录本次运行写入的所有路径。退出时直接 unlink 即可。
//        孤儿清理走文件名前缀扫描（`.paperlink-preview-` + `.html`）。
//

import Foundation

/// 临时预览文件的命名规则（HTMLPreview 写入时也用这个前缀）
enum PreviewFileNames {
    static let prefix = ".paperlink-preview-"
    static let suffix = ".html"

    static func isPreviewFile(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(suffix)
    }

    /// 构造一个文件名
    static func name(forHash hash: Int) -> String {
        "\(prefix)\(hash)\(suffix)"
    }
}

final class PreviewFileCleaner {
    static let shared = PreviewFileCleaner()
    private init() {}

    /// 本次 App 运行期间写入的所有 preview 文件路径。
    /// 退出时（willTerminate）遍历删除，避免用户 .pml 目录堆积垃圾。
    private var written: Set<URL> = []

    /// 标记一个文件由本次运行产生（成功写入后调用）。
    func registerWritten(_ url: URL) {
        written.insert(url)
    }

    /// 应用退出时调用：删除本次运行产生的全部文件。
    func cleanupAllWritten() {
        let fm = FileManager.default
        var removed = 0
        for url in written {
            do {
                try fm.removeItem(at: url)
                removed += 1
            } catch {
                // 静默失败：文件可能已被外部删除 / 权限问题
                #if DEBUG
                print("[PreviewCleaner] remove failed: \(url.lastPathComponent): \(error)")
                #endif
            }
        }
        #if DEBUG
        if removed > 0 {
            print("[PreviewCleaner] cleanup: removed \(removed) preview files")
        }
        #endif
        written.removeAll()
    }

    /// 扫描一个目录，删除里面所有 `.paperlink-preview-*.html` 孤儿。
    /// 用于启动时扫 Bundle.resources / 最近打开的 .pml 目录，以及切换 rootURL 时扫当前目录。
    /// - Returns: 删除的文件数
    @discardableResult
    func sweepOrphans(in directory: URL) -> Int {
        let fm = FileManager.default
        // 不带 .skipsHiddenFiles：preview 文件名以 . 开头（隐藏文件），要包含进来
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return 0 }

        var removed = 0
        for url in entries {
            guard PreviewFileNames.isPreviewFile(url.lastPathComponent) else { continue }
            // 跳过本次刚写入的（不要删除正在用的）
            if written.contains(url) { continue }
            do {
                try fm.removeItem(at: url)
                removed += 1
            } catch {
                #if DEBUG
                print("[PreviewCleaner] sweep failed: \(url.lastPathComponent): \(error)")
                #endif
            }
        }
        #if DEBUG
        if removed > 0 {
            print("[PreviewCleaner] sweep \(directory.path): removed \(removed) orphans")
        }
        #endif
        return removed
    }

    /// 启动时调用：扫 Bundle.resources + Open Recent 列表里的目录。
    /// （Open Recent 是上次应用期间打开的 .pml 文件，所以它们的目录可能残留孤儿）
    func cleanupOnStartup() {
        // 1. Bundle.resources（demo.pml 时写到这）
        if let bundleResources = Bundle.main.resourceURL {
            sweepOrphans(in: bundleResources)
        }

        // 2. Open Recent 列表里每个 .pml 的父目录
        if let recentsData = UserDefaults.standard.array(forKey: "PaperLink.recentBookmarks") as? [Data] {
            var seenDirs: Set<URL> = []
            for bookmarkData in recentsData {
                var isStale = false
                guard let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) else { continue }
                // Release sandbox 下必须 startAccessing 才能 unlink
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
                if seenDirs.insert(dir).inserted {
                    sweepOrphans(in: dir)
                }
            }
        }
    }
}

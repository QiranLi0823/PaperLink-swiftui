//
//  PaperDocument.swift
//  PaperLink
//
//  Phase 0.2: 持有 PaperML AST + 渲染出的 HTML。
//  source 变化 → debounce 200ms → parse → render HTML。
//
//  Phase 1 Sprint 6：文件持久化改 security-scoped bookmark（为 Sprint 7 sandbox 做准备）。
//    - UserDefaults["PaperLink.lastOpenedBookmark"]: Data
//    - UserDefaults["PaperLink.recentBookmarks"]: [Data]  (Open Recent 列表)
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class PaperDocument: ObservableObject {
    @Published var source: String = ""
    @Published var document: PaperMLDocument?
    @Published var html: String = "<p>解析中…</p>"
    @Published var errors: [ParseError] = []
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false

    private static let lastBookmarkKey = "PaperLink.lastOpenedBookmark"
    private static let recentBookmarksKey = "PaperLink.recentBookmarks"
    private static let recentLimit = 10

    /// 当前文件是否处于 security-scoped 状态（sandbox 下需要）
    private var currentScopedURL: URL?
    private var lastSavedSource: String = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 启动时尝试加载上次打开的文件
        let initial: String
        let initialURL: URL?
        if let url = Self.resolveLastOpenedBookmark() {
            do {
                let text = try ProjectManager.shared.load(from: url)
                initial = text
                initialURL = url
            } catch {
                initial = Self.loadBundledDemo()
                initialURL = nil
            }
        } else {
            initial = Self.loadBundledDemo()
            initialURL = nil
        }

        self.source = initial
        self.fileURL = initialURL
        self.lastSavedSource = initial
        self.recompute(initial)

        // 监听 sidebar 文件树点击
        NotificationCenter.default.addObserver(
            forName: .paperLinkOpenFile,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let url = note.object as? URL {
                self?.open(url: url)
            }
        }

        $source
            .removeDuplicates()
            .sink { [weak self] newSource in
                guard let self = self else { return }
                self.isDirty = (newSource != self.lastSavedSource)
                self.recomputeDebounced(newSource)
            }
            .store(in: &cancellables)

        $source
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] newSource in
                self?.recompute(newSource)
            }
            .store(in: &cancellables)
    }

    private func recompute(_ source: String) {
        let result = PaperMLParser.parseWithErrors(source)
        let doc = result.document ?? PaperMLDocument(metadata: .init(), sections: [])
        // 用当前 .pml 文件所在目录作为图片根，让 @path = "figures/x.png" 解析到
        // 同目录的 figures/x.png（而不是 Bundle.main）。
        let rendered = HTMLRenderer.render(doc, rootURL: fileURL)
        self.document = doc
        self.html = rendered
        self.errors = result.errors
    }

    private func recomputeDebounced(_ source: String) {
        // 占位（debounced sink 调 recompute(_:)）
    }

    // MARK: - 文件 I/O

    func open(url: URL) {
        // 先 release 上一个 scoped url
        releaseScopedResource()

        let resolved = startAccessing(url)
        do {
            let text = try ProjectManager.shared.load(from: url)
            self.fileURL = url
            self.source = text
            self.lastSavedSource = text
            self.isDirty = false
            self.currentScopedURL = resolved
            // 存 bookmark + 写 recent list
            Self.storeBookmark(for: url)
            Self.pushRecent(url: url)
        } catch {
            print("打开失败：\(error)")
            stopAccessing(resolved)
        }
    }

    func save() {
        if let url = fileURL {
            save(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let suggestedName = fileURL?.lastPathComponent ?? "untitled.pml"
        ProjectManager.shared.savePanel(suggestedName: suggestedName) { [weak self] url in
            guard let self = self, let url = url else { return }
            self.save(to: url)
        }
    }

    /// 同目录下重命名
    func rename(to newName: String) {
        guard let oldURL = fileURL else { return }
        let parent = oldURL.deletingLastPathComponent()
        let newURL = parent.appendingPathComponent(newName)
        guard newURL != oldURL else { return }
        do {
            try ProjectManager.shared.save(source, to: newURL)
            // 删除旧文件
            try? FileManager.default.removeItem(at: oldURL)
            self.fileURL = newURL
            // bookmark 跟着换
            Self.storeBookmark(for: newURL)
            Self.replaceRecent(oldURL: oldURL, newURL: newURL)
        } catch {
            print("重命名失败：\(error)")
        }
    }

    private func save(to url: URL) {
        do {
            try ProjectManager.shared.save(source, to: url)
            self.fileURL = url
            self.lastSavedSource = source
            self.isDirty = false
            Self.storeBookmark(for: url)
            Self.pushRecent(url: url)
        } catch {
            print("保存失败：\(error)")
        }
    }

    private static func loadBundledDemo() -> String {
        if let url = Bundle.main.url(forResource: "demo", withExtension: "pml"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "@section{示例}\n\n加载 demo.pml 失败。"
    }

    // MARK: - Security-Scoped Bookmark

    /// 把 url 存成 security-scoped bookmark，写到 UserDefaults 的 lastOpenedBookmark
    private static func storeBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: lastBookmarkKey)
        } catch {
            // bookmark 创建失败时退回存 path（sandbox=NO 时足够）
            UserDefaults.standard.set(url.path, forKey: lastBookmarkKey)
        }
    }

    /// 启动时解析 lastOpenedBookmark，返回有效 URL（已 startAccessing）；失败返回 nil
    private static func resolveLastOpenedBookmark() -> URL? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: lastBookmarkKey) else {
            // 兼容旧的 path 存储
            if let path = defaults.string(forKey: lastBookmarkKey),
               FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            // 启动时 startAccessing 一次，让整个 app 生命周期内能读
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            print("解析 bookmark 失败：\(error)")
            return nil
        }
    }

    /// 打开新文件时 startAccessing（沙箱下需要）
    private func startAccessing(_ url: URL) -> URL? {
        let did = url.startAccessingSecurityScopedResource()
        return did ? url : nil
    }

    /// 释放上一个 scoped url
    private func releaseScopedResource() {
        if let old = currentScopedURL {
            old.stopAccessingSecurityScopedResource()
            currentScopedURL = nil
        }
    }

    private func stopAccessing(_ url: URL?) {
        url?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Recent Bookmarks

    /// 获取最近打开的文件列表（最近的在最前），附带显示用 path
    static func recentFiles() -> [(url: URL, path: String)] {
        let defaults = UserDefaults.standard
        guard let datas = defaults.array(forKey: recentBookmarksKey) as? [Data] else {
            return []
        }
        var result: [(URL, String)] = []
        for data in datas {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                result.append((url, url.path))
            }
        }
        return result
    }

    /// 把 url 推到 recent list 头部
    private static func pushRecent(url: URL) {
        let defaults = UserDefaults.standard
        var datas = (defaults.array(forKey: recentBookmarksKey) as? [Data]) ?? []

        // 用现有 bookmark 数据对比去重（不创建新 bookmark 节省 IO）
        let newData: Data
        do {
            newData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return
        }
        datas.removeAll { data in
            // 比较：都解析成 path 后对比
            var stale = false
            if let existing = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return existing.standardizedFileURL == url.standardizedFileURL
            }
            return false
        }
        datas.insert(newData, at: 0)
        if datas.count > recentLimit {
            datas = Array(datas.prefix(recentLimit))
        }
        defaults.set(datas, forKey: recentBookmarksKey)
        NotificationCenter.default.post(name: .paperLinkRecentChanged, object: nil)
    }

    /// 重命名时替换 recent list 中的旧 url
    private static func replaceRecent(oldURL: URL, newURL: URL) {
        let defaults = UserDefaults.standard
        guard var datas = defaults.array(forKey: recentBookmarksKey) as? [Data] else { return }
        for i in datas.indices {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: datas[i],
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), resolved.standardizedFileURL == oldURL.standardizedFileURL {
                if let newData = try? newURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    datas[i] = newData
                }
            }
        }
        defaults.set(datas, forKey: recentBookmarksKey)
        NotificationCenter.default.post(name: .paperLinkRecentChanged, object: nil)
    }

    static func clearRecent() {
        UserDefaults.standard.removeObject(forKey: recentBookmarksKey)
        NotificationCenter.default.post(name: .paperLinkRecentChanged, object: nil)
    }
}

extension Notification.Name {
    static let paperLinkRecentChanged = Notification.Name("PaperLink.recentChanged")
}

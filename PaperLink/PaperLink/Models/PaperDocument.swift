//
//  PaperDocument.swift
//  PaperLink
//
//  Phase 0.2: 持有 PaperML AST + 渲染出的 HTML。
//  source 变化 → debounce 200ms → parse → render HTML。
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

    private static let lastFileKey = "PaperLink.lastOpenedFilePath"

    private var lastSavedSource: String = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 启动时尝试加载上次打开的文件
        let initial: String
        let initialURL: URL?
        if let path = UserDefaults.standard.string(forKey: Self.lastFileKey),
           FileManager.default.fileExists(atPath: path) {
            do {
                let text = try ProjectManager.shared.load(from: URL(fileURLWithPath: path))
                initial = text
                initialURL = URL(fileURLWithPath: path)
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
        let rendered = HTMLRenderer.render(doc)
        self.document = doc
        self.html = rendered
        self.errors = result.errors
    }

    private func recomputeDebounced(_ source: String) {
        // 占位（debounced sink 调 recompute(_:)）
    }

    // MARK: - 文件 I/O

    func open(url: URL) {
        do {
            let text = try ProjectManager.shared.load(from: url)
            self.fileURL = url
            self.source = text
            self.lastSavedSource = text
            self.isDirty = false
            UserDefaults.standard.set(url.path, forKey: Self.lastFileKey)
        } catch {
            print("打开失败：\(error)")
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
            UserDefaults.standard.set(newURL.path, forKey: Self.lastFileKey)
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
            UserDefaults.standard.set(url.path, forKey: Self.lastFileKey)
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
}

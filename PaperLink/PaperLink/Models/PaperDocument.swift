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

    private var cancellables = Set<AnyCancellable>()

    init() {
        let initial = Self.loadInitialSource()
        self.source = initial
        self.recompute(initial)

        $source
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] newSource in
                self?.recompute(newSource)
            }
            .store(in: &cancellables)
    }

    private func recompute(_ source: String) {
        let doc = PaperMLParser.parse(source)
        let rendered = HTMLRenderer.render(doc)
        self.document = doc
        self.html = rendered
    }

    private static func loadInitialSource() -> String {
        if let url = Bundle.main.url(forResource: "demo", withExtension: "pml"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return """
        @section{示例}

        加载 demo.pml 失败。
        请确认 PaperLink/Resources/demo.pml 已加入 Bundle。
        """
    }
}

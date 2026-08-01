//
//  ContentView.swift
//  PaperLink
//
//  Phase 0.2: 双栏，左 TextEditor，右 WKWebView 渲染 HTML。
//  完整论文样式（标题 / 作者 / Abstract / 章节 / 公式 / 表格 / 图占位 / 引用角标）。
//

import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var document = PaperDocument()

    var body: some View {
        HSplitView {
            // 左侧：PaperML 源
            VStack(alignment: .leading, spacing: 4) {
                Text("PaperML 源（demo.pml）")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $document.source)
                    .font(.system(.body, design: .monospaced))
                    .border(Color.gray.opacity(0.3))
            }
            .padding(8)
            .frame(minWidth: 320)

            // 右侧：HTML 预览
            VStack(alignment: .leading, spacing: 4) {
                Text("论文预览")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HTMLPreview(html: document.html)
                    .border(Color.gray.opacity(0.3))
            }
            .padding(8)
            .frame(minWidth: 420)
        }
        .frame(minWidth: 1100, minHeight: 700)
    }
}

// MARK: - WKWebView 包装

struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // baseURL 设为 Bundle.resourceURL，让 <img src="file://..."> 能解析
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }
}

#Preview {
    ContentView()
}

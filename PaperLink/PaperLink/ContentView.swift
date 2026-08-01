//
//  ContentView.swift
//  PaperLink
//
//  Phase 1 Sprint 2+：三栏布局（sidebar + editor + preview）+ 紧凑 toolbar。
//

import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var document: PaperDocument
    @EnvironmentObject private var sidebarState: SidebarState
    @State private var isRenaming = false
    @State private var renameText = ""
    @StateObject private var treeManager = ProjectTreeManager()

    var body: some View {
        VStack(spacing: 0) {
            // 紧凑 toolbar：只在重命名时出现
            compactToolbar

            HStack(spacing: 0) {
                // 左侧 sidebar（activeMode 非 nil 时显示）
                if sidebarState.isVisible {
                    SidebarView(
                        treeManager: treeManager,
                        activeMode: $sidebarState.activeMode,
                        currentFileURL: document.fileURL
                    )
                    .frame(width: 220)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                // 右侧：editor + preview 1:1
                HSplitView {
                    LineNumberedEditor(text: $document.source, errors: document.errors)
                        .padding(8)
                        .frame(minWidth: 380)

                    HTMLPreview(html: document.html)
                        .padding(8)
                        .frame(minWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: sidebarState.activeMode)

            StatusBar(errors: document.errors)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("PaperLink")
        .onReceive(NotificationCenter.default.publisher(for: .paperLinkStartRename)) { _ in
            startRename()
        }
        .onChange(of: document.fileURL) { _, newURL in
            treeManager.reload(from: newURL)
        }
        .onAppear {
            treeManager.reload(from: document.fileURL)
        }
    }

    private var currentFileName: String {
        document.fileURL?.lastPathComponent ?? "Untitled.pml"
    }

    @ViewBuilder
    private var compactToolbar: some View {
        // toolbar 留空：sidebar 按钮已经移到窗口标题栏（PaperLinkApp.toolbar）
        EmptyView()
    }

    private func startRename() {
        renameText = currentFileName
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != currentFileName {
            document.rename(to: trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
        renameText = currentFileName
    }
}

// MARK: - WKWebView 包装

struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }
}

// MARK: - 状态栏

struct StatusBar: View {
    let errors: [ParseError]

    var body: some View {
        HStack(spacing: 8) {
            if let first = errors.first {
                Image(systemName: first.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(first.severity == .error ? Color(nsColor: .systemRed) : Color(nsColor: .systemOrange))
                Text("\(errors.count) 个错误")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(first.shortDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text("解析正常")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(PaperDocument())
        .environmentObject(SidebarState.shared)
}
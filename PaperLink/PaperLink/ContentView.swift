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

                    HTMLPreview(html: document.html, fileURL: document.fileURL)
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
        .navigationTitle(windowTitle)
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

    /// 窗口标题：未保存时加 `*` 标记
    /// 例：`demo.pml*` / `demo.pml` / `Untitled.pml*`
    private var windowTitle: String {
        let name = currentFileName
        return document.isDirty ? "\(name)*" : name
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

/// 策略：把 HTML 写到 rootURL **之内**的临时文件 + `loadFileURL` 加载。
///
/// 为什么不用 `loadHTMLString`：
///   - `loadHTMLString` 内部走 about:blank scheme，WKWebView 在 macOS 上从 about:blank
///     加载 file:// 资源行为不一致
///
/// 为什么 HTML 必须写在 rootURL 内：
///   - WKWebView 解析 `<img src="figures/x.png">` 相对路径是基于 HTML 文件自身的位置
///   - 如果 HTML 写在 `/tmp/paperlink-preview.html`，相对路径会解析到 `/tmp/figures/...`，图就找不到
///   - 写在 rootURL 内（比如 `~/Documents/papers/.paperlink-preview.html`），
///     相对路径自动解析到 `~/Documents/papers/figures/x.png`
///
/// rootURL 决定图片所在的目录：
///   - fileURL != nil → rootURL = fileURL 所在目录（图片走同目录 figures/）
///   - fileURL == nil → rootURL = Bundle.main.resourceURL（demo 图走 bundle 内 figures/）
///
/// 临时文件名：`.paperlink-preview.html`（隐藏文件，避免污染文件列表）。
struct HTMLPreview: NSViewRepresentable {
    let html: String
    let fileURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let rootURL: URL
        if let fileURL = fileURL {
            rootURL = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
        } else {
            rootURL = Bundle.main.resourceURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }

        // 幂等：html/rootURL 都没变就跳过
        let key = "\(html.hashValue)-\(rootURL.path)"
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key

        // 把 HTML 写到 rootURL 内
        let previewFile = rootURL.appendingPathComponent(".paperlink-preview.html")
        do {
            try html.write(to: previewFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(previewFile, allowingReadAccessTo: rootURL)
        } catch {
            // 写失败 fallback 到 loadHTMLString
            webView.loadHTMLString(html, baseURL: rootURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastKey: String?
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
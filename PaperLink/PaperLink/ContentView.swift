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

                // 右侧：editor + preview 1:1（可拖动 + 持久化比例）
                SplitContainer(document: document)
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

/// 策略：HTML 写到 `rootURL` 之内的临时文件（`.paperlink-preview-<hash>.html`），
/// 然后用 `loadFileURL(allowingReadAccessTo: rootURL)` 加载。
///
/// 为什么 HTML 必须写在 `rootURL` 内：
///   - WKWebView 在 macOS 上要求 `loadFileURL` 的 URL **必须**在 `allowingReadAccessTo` 之内
///     （否则 sandbox 拒绝：`url is not inside resource directory url`）
///   - 写在 `rootURL` 内 → 同一目录 → sandbox 放行 → 同时 `<img src="figures/x.png">` 也能直接解析
///
/// 为什么不在 `~/Library/Application Support/` 写：
///   - 那就需要 `allowingReadAccessTo: appSupportDir + rootURL`（两个目录），
///     macOS WKWebView 不支持 multi-root allowingReadAccessTo
///
/// Dev vs Release 写权限：
///   - Dev（sandbox=NO）：`Resources/` 可写 → 直接写 → OK
///   - Release（sandbox=YES）：`Resources/` 在 app bundle 里**只读** → 写失败 → fallback
///     但 Release 也不会触发（Xcode source-synced Resources 不存在），
///     用户文档目录是 sandbox 下的 user-selected，是可写的
///
/// HTML 临时文件名：`.paperlink-preview-<hash>.html`（隐藏文件，避免污染文件列表，
/// hash 后缀保证不同内容不互相覆盖）。
///
/// rootURL 决定图片所在的目录：
///   - fileURL != nil → rootURL = fileURL 所在目录（图片走同目录 figures/）
///   - fileURL == nil → rootURL = Bundle.main.resourceURL（demo 图走 bundle 内 figures/）
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
        print("[HTMLPreview] rootURL=\(rootURL.path), html length=\(html.count)")

        // 幂等：html/rootURL 都没变就跳过
        let key = "\(html.hashValue)-\(rootURL.path)"
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key

        // 把 HTML 写到 rootURL 内：保证 WKWebView sandbox 允许 + 相对路径解析正确
        let previewFile = rootURL.appendingPathComponent(".paperlink-preview-\(html.hashValue).html")
        do {
            try html.write(to: previewFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(previewFile, allowingReadAccessTo: rootURL)
        } catch {
            // rootURL 只读（Xcode bundle / 某些 sandbox 场景）→ fallback
            // loadHTMLString + baseURL 在 macOS WKWebView 上不能读 file:// 资源，
            // 但至少能让用户看到 HTML 骨架（图的 alt 文字、CSS 样式）。
            print("[HTMLPreview] write failed: \(error) -> fallback loadHTMLString")
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
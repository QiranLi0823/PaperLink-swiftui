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

    // Sprint 8.4：⌘F 查找条
    @State private var showFindBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            compactToolbar

            HStack(spacing: 0) {
                if sidebarState.isVisible {
                    SidebarView(
                        treeManager: treeManager,
                        activeMode: $sidebarState.activeMode,
                        currentFileURL: document.fileURL
                    )
                    .frame(width: 220)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                SplitContainer(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: sidebarState.activeMode)
            // Sprint 8.4 FindBar 浮层
            .overlay(alignment: .topTrailing) {
                if showFindBar {
                    FindBar(
                        query: $searchQuery,
                        matchCount: $matchCount,
                        currentIndex: $currentMatchIndex,
                        onPrev: {
                            NotificationCenter.default.post(name: .paperLinkFindGotoMatch, object: nil, userInfo: ["next": false])
                        },
                        onNext: {
                            NotificationCenter.default.post(name: .paperLinkFindGotoMatch, object: nil, userInfo: ["next": true])
                        },
                        onClose: {
                            showFindBar = false
                            searchQuery = ""
                            NotificationCenter.default.post(name: .paperLinkFindQueryChanged, object: nil, userInfo: ["query": ""])
                        }
                    )
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showFindBar)

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
        // ⌘F 打开查找条
        .background(
            Button("") { showFindBar = true }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // 监听 searchQuery 变化 → post 给 editor
        .onChange(of: searchQuery) { _, newQuery in
            NotificationCenter.default.post(name: .paperLinkFindQueryChanged, object: nil, userInfo: ["query": newQuery])
        }
        // 监听 editor 回报 matchCount / currentIndex
        .onReceive(NotificationCenter.default.publisher(for: .paperLinkFindMatchCount)) { note in
            matchCount = (note.userInfo?["count"] as? Int) ?? 0
            currentMatchIndex = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .paperLinkFindCurrentIndex)) { note in
            currentMatchIndex = (note.userInfo?["index"] as? Int) ?? 0
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
import SwiftUI
import WebKit

struct HTMLPreview: NSViewRepresentable {
    let html: String
    let fileURL: URL?
    /// Sprint 9：跟随光标模式开关。
    let followCursorMode: Bool
    /// Sprint 9.12：anchor 共享 channel（单例引用类型）。updateNSView 每次都读取最新值。
    let anchorProvider: () -> BlockAnchor?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Sprint 9.5：注入 scrollToFraction；Sprint 9.7：scrollToBlock 用真实 DOM 锚点
        let script = """
        (function() {
            var lastKind = null, lastIndex = -1, lastProgress = 0;

            function applyFraction(f) {
                try {
                    var max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                    var target = f * document.documentElement.scrollHeight - window.innerHeight / 2;
                    if (target < 0) target = 0;
                    if (target > max) target = max;
                    window.scrollTo(0, target);
                } catch (e) {}
            }
            function applyBlock(kind, index, progress) {
                try {
                    var sel = '[data-block-kind="' + kind + '"][data-block-index="' + index + '"]';
                    var el = document.querySelector(sel);
                    if (!el) return false;
                    var rect = el.getBoundingClientRect();
                    if (rect.height === 0) {
                        try { el.scrollIntoView({block: 'center'}); return true; } catch(e) {}
                        return false;
                    }
                    var docTop = rect.top + window.scrollY;
                    var targetY = docTop + progress * rect.height - window.innerHeight / 2;
                    var max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                    if (targetY < 0) targetY = 0;
                    if (targetY > max) targetY = max;
                    var delta = targetY - window.scrollY;
                    // 50px 死区：用户在小间距块间切换时屏蔽视觉抖动
                    if (Math.abs(delta) < 50) return true;
                    window.scrollTo(0, targetY);
                    return true;
                } catch (e) {
                    return false;
                }
            }
            function reapply() {
                if (lastKind == null) return;
                applyBlock(lastKind, lastIndex, lastProgress);
            }

            window.scrollToFraction = applyFraction;
            window.scrollToBlock = function(kind, index, progress) {
                lastKind = kind;
                lastIndex = index;
                lastProgress = progress;
                return applyBlock(kind, index, progress);
            };

            // 图片 async decode / KaTeX async 渲染导致 DOM 节点延后出现或 height 变化，
            // 用 MutationObserver + ResizeObserver + load 持续 reapply。
            if (window.ResizeObserver) {
                new ResizeObserver(reapply).observe(document.documentElement);
            }
            new MutationObserver(reapply).observe(document.body, { childList: true, subtree: true, attributes: true });
            window.addEventListener('load', reapply);
            if (document.readyState === 'complete') reapply();
        })();
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        // 把 Coordinator 同时注册为 message handler（备用通道；目前不主动用）
        config.userContentController.add(context.coordinator, name: "paperLink")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let rootURL: URL
        if let fileURL = fileURL {
            rootURL = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
        } else {
            rootURL = Bundle.main.resourceURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }

        // 幂等：html/rootURL 都没变就跳过文件写入；但 anchor channel 变了 → 立刻 evaluate
        let key = "\(html.hashValue)-\(rootURL.path)"
        let htmlChanged = (context.coordinator.lastKey != key)
        if htmlChanged {
            context.coordinator.lastKey = key
            let previewFile = rootURL.appendingPathComponent(".paperlink-preview-\(html.hashValue).html")
            do {
                try html.write(to: previewFile, atomically: true, encoding: .utf8)
                webView.loadFileURL(previewFile, allowingReadAccessTo: rootURL)
            } catch {
                print("[HTMLPreview] write failed: \(error) -> fallback loadHTMLString")
                webView.loadHTMLString(html, baseURL: rootURL)
            }
        }

        // Sprint 9.12：从共享 channel 读取最新 anchor（每次 updateNSView 都查）。
        // 简化：去掉 lastAnchor 缓存（避免 stale 状态），每次 html 加载完成或 anchor 更新都 evaluate。
        if followCursorMode, let a = anchorProvider() {
            context.coordinator.lastAnchor = a
            // escape kind（JS 字符串字面量安全）
            let kindJS = a.kind
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function() {
                var ok = window.scrollToBlock('\(kindJS)', \(a.index), \(Double(a.progress)));
                var info = {
                    ok: ok,
                    target: '\(kindJS)',
                    index: \(a.index),
                    progress: \(Double(a.progress)),
                    scrollY: window.scrollY,
                    scrollHeight: document.documentElement.scrollHeight,
                    viewportH: window.innerHeight,
                    blockCount: document.querySelectorAll('[data-block-kind="\(kindJS)"]').length
                };
                console.log('[FollowCursor]', JSON.stringify(info));
                return JSON.stringify(info);
            })();
            """
            webView.evaluateJavaScript(js) { result, error in
                if let resultStr = result as? String {
                    print("[FollowCursor/JS] \(resultStr)")
                }
                if let error = error {
                    print("[FollowCursor/JS] error: \(error)")
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        // Sprint 9.12：Coordinator 直接监听 paperLinkFollowCursorAnchor，
        // 避免 SwiftUI 不感知 AnchorProvider 变化导致 updateNSView 不触发。
        let coord = Coordinator()
        NotificationCenter.default.addObserver(
            coord,
            selector: #selector(Coordinator.onFollowCursorAnchor(_:)),
            name: .paperLinkFollowCursorAnchor,
            object: nil
        )
        return coord
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // 防止 leak：把 userContentController 上注册的 handler / script 清掉
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "paperLink")
        NotificationCenter.default.removeObserver(coordinator)
    }

    /// Sprint 9.7：Coordinator 仅承担 WKScriptMessageHandler / WKNavigationDelegate 角色。
    /// Sprint 9.12：Coordinator 直接监听 `paperLinkFollowCursorAnchor` 通知，
    /// 缓存到 self.pendingAnchor，并在 didFinish / updateNSView 触发 evaluate。
    /// 这是因为 SwiftUI 不感知 AnchorProvider 引用变化，必须显式 push。
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastKey: String?
        var lastAnchor: BlockAnchor?
        var pendingAnchor: BlockAnchor?
        weak var webView: WKWebView?

        @MainActor
        @objc func onFollowCursorAnchor(_ note: Notification) {
            // Sprint 9.15：按钮关闭时直接 no-op，不再 evaluate。
            // 源头（LineNumberedEditor.postFollowCursorFraction）已 gate，
            // 这里再守一道防止别处误发通知时 preview 失控跟随。
            guard SidebarState.shared.followCursorMode else { return }
            guard let userInfo = note.userInfo,
                  let kind = userInfo["kind"] as? String,
                  let index = userInfo["index"] as? Int,
                  let progress = userInfo["progress"] as? Double else { return }
            let a = BlockAnchor(kind: kind, index: index, progress: CGFloat(progress))
            pendingAnchor = a
            // 立即 evaluate（不等 updateNSView，避免 SwiftUI 不刷新）
            if let wv = webView {
                evaluateJS(on: wv, anchor: a)
            }
        }

        @MainActor
        private func evaluateJS(on webView: WKWebView, anchor: BlockAnchor) {
            let kindJS = anchor.kind
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function() {
                var ok = window.scrollToBlock('\(kindJS)', \(anchor.index), \(Double(anchor.progress)));
                var info = {
                    ok: ok,
                    target: '\(kindJS)',
                    index: \(anchor.index),
                    progress: \(Double(anchor.progress)),
                    scrollY: window.scrollY,
                    scrollHeight: document.documentElement.scrollHeight,
                    viewportH: window.innerHeight,
                    blockCount: document.querySelectorAll('[data-block-kind="\(kindJS)"]').length
                };
                console.log('[FollowCursor]', JSON.stringify(info));
                return JSON.stringify(info);
            })();
            """
            webView.evaluateJavaScript(js) { result, error in
                if let resultStr = result as? String {
                    print("[FollowCursor/JS] \(resultStr)")
                }
                if let error = error {
                    print("[FollowCursor/JS] error: \(error)")
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // 备用通道：JS 主动发消息到 Swift。当前未使用。
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 加载完成：用 pendingAnchor 重试（不依赖 lastAnchor 比较）
            if let a = pendingAnchor {
                evaluateJS(on: webView, anchor: a)
            }
        }
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
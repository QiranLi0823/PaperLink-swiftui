//
//  EditorSplitViewController.swift
//  PaperLink
//
//  Phase 1 Sprint 4：HSplitView → NSSplitViewController。
//  可拖动 splitter + 比例持久化。
//
//  架构：
//    ContentView (SwiftUI)
//      └── SplitContainer (NSViewControllerRepresentable)
//            └── EditorSplitViewController : NSSplitViewController
//                  ├── [0] EditorPaneVC : NSViewController
//                  │     └── LineNumberedEditor (NSViewRepresentable → NSHostingView)
//                  └── [1] PreviewPaneVC : NSViewController
//                        └── HTMLPreview (NSViewRepresentable → NSHostingView)
//

import AppKit
import SwiftUI
import Combine

/// 持久化 key：split 比例（0.0 - 1.0，editor 占的比例）
private let kSplitFractionKey = "PaperLink.splitFraction"

/// editor / preview 各自的最小宽度
private let kMinPaneWidth: CGFloat = 380

final class EditorSplitViewController: NSSplitViewController {

    private let editorItem: NSSplitViewItem
    private let previewItem: NSSplitViewItem

    private let document: PaperDocument

    /// 拖动时实时写 UserDefaults 的 debouncer
    private var saveDebouncer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(document: PaperDocument) {
        self.document = document

        // Editor pane（SwiftUI view → NSHostingController → NSViewController）
        let editorVC = EditorPaneVC(document: document)
        self.editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = kMinPaneWidth
        editorItem.canCollapse = false
        editorItem.titlebarSeparatorStyle = .none

        // Preview pane
        let previewVC = PreviewPaneVC(document: document)
        self.previewItem = NSSplitViewItem(viewController: previewVC)
        previewItem.minimumThickness = kMinPaneWidth
        previewItem.canCollapse = false
        previewItem.titlebarSeparatorStyle = .none

        super.init(nibName: nil, bundle: nil)

        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

        // 默认等宽（首次启动，UserDefaults 没值）
        splitView.isVertical = true
        splitView.dividerStyle = .thin
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 启动时恢复比例
        let saved = UserDefaults.standard.double(forKey: kSplitFractionKey)
        if saved > 0.01 && saved < 0.99 {
            splitView.setPosition(saved * splitView.bounds.width,
                                  ofDividerAt: 0)
        }
        // 没保存值 → 1:1（viewDidLayout 后由 layout 处理）

        // 拖动时监听
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )

        // Sprint 9.12：将 editor 发出的 anchor 通知写入 AnchorProvider 单例，
        // HTMLPreview.updateNSView 轮询最新值（避免 @State 链路丢值）。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onFollowCursorAnchor(_:)),
            name: .paperLinkFollowCursorAnchor,
            object: nil
        )
    }

    @objc private func onFollowCursorAnchor(_ note: Notification) {
        guard SidebarState.shared.followCursorMode,
              let kind = note.userInfo?["kind"] as? String,
              let index = note.userInfo?["index"] as? Int,
              let progress = note.userInfo?["progress"] as? Double else { return }
        AnchorProvider.shared.current = BlockAnchor(kind: kind, index: index, progress: CGFloat(progress))
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 首次 layout：没保存值 → 等分
        if UserDefaults.standard.object(forKey: kSplitFractionKey) == nil {
            let total = splitView.bounds.width
            if total > 0 {
                splitView.setPosition(total / 2, ofDividerAt: 0)
            }
        }
    }

    @objc private func splitViewDidResize() {
        // debounce 200ms 后写 UserDefaults（避免拖动期间频繁 IO）
        saveDebouncer?.invalidate()
        saveDebouncer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let total = self.splitView.bounds.width
            guard total > 0 else { return }
            let pos = self.splitView.dividerThickness + self.editorItem.viewController.view.frame.width
            let fraction = pos / total
            UserDefaults.standard.set(fraction, forKey: kSplitFractionKey)
        }
    }

    deinit {
        saveDebouncer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Editor Pane

/// Editor Pane：包装 LineNumberedEditor（NSViewRepresentable）。
/// 用 NSHostingController 让 SwiftUI view 嵌入 NSViewController，
/// 并通过 @ObservedObject 监听 document 变化自动刷新。
final class EditorPaneVC: NSViewController {
    private let document: PaperDocument
    private var hosting: NSHostingView<EditorPaneContent>!

    init(document: PaperDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        hosting = NSHostingView(rootView: EditorPaneContent(document: document))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.view = hosting
    }
}

/// EditorPane 的 SwiftUI 内容，订阅 document 自动重渲
private struct EditorPaneContent: View {
    @ObservedObject var document: PaperDocument

    var body: some View {
        LineNumberedEditor(
            text: Binding(
                get: { document.source },
                set: { document.source = $0 }
            ),
            errors: document.errors
        )
        .padding(8)
    }
}

// MARK: - Preview Pane

/// Preview Pane：包装 HTMLPreview（NSViewRepresentable）。
/// @ObservedObject 让 fileURL 切换时自动重新 load HTML（更新 WKWebView baseURL）。
final class PreviewPaneVC: NSViewController {
    private let document: PaperDocument
    private var hosting: NSHostingView<PreviewPaneContent>!

    init(document: PaperDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        hosting = NSHostingView(rootView: PreviewPaneContent(document: document))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.view = hosting
    }
}

/// PreviewPane 的 SwiftUI 内容，订阅 document 自动重渲；
/// Sprint 9.12：移除 onReceive 链路，改由 Coordinator 自己监听 NotificationCenter 直接转发到 JS，
/// 避免 @State 在 document 变化时 body 重算导致的 stale state 问题。
private struct PreviewPaneContent: View {
    @ObservedObject var document: PaperDocument
    @ObservedObject private var sidebarState = SidebarState.shared

    var body: some View {
        HTMLPreview(
            html: document.html,
            fileURL: document.fileURL,
            followCursorMode: sidebarState.followCursorMode,
            anchorProvider: { AnchorProvider.shared.current }
        )
        .padding(8)
        .onChange(of: sidebarState.followCursorMode) { newValue in
            if newValue {
                // Sprint 9.16：off → on 主动触发一次滚动（不等下一次 selectionChanged）。
                // Editor 端响应后用当前光标行算 anchor 并 post 通知。
                NotificationCenter.default.post(name: .paperLinkFollowCursorEnabled, object: nil)
            } else {
                AnchorProvider.shared.current = nil
            }
        }
    }
}

/// Sprint 9.12：跨 SwiftUI/HtmlPreview 边界的 anchor 共享 channel。
/// Coordinator 监听 `paperLinkFollowCursorAnchor` 写入这里；HTMLPreview.updateNSView 读取最新值。
/// 用单例 + 引用类型，避免 `@State` 在 body 重算时丢值。
final class AnchorProvider {
    static let shared = AnchorProvider()
    var current: BlockAnchor?
    private init() {}
}

/// Sprint 9.7：editor → preview 锚点（kind + index + 块内进度）
struct BlockAnchor: Equatable {
    let kind: String
    let index: Int
    let progress: CGFloat
}

// MARK: - SwiftUI Wrapper

/// 把 EditorSplitViewController 暴露给 SwiftUI。
struct SplitContainer: NSViewControllerRepresentable {
    let document: PaperDocument

    func makeNSViewController(context: Context) -> EditorSplitViewController {
        EditorSplitViewController(document: document)
    }

    func updateNSViewController(_ vc: EditorSplitViewController, context: Context) {
        // SwiftUI 端 document 没变化时无需更新；LineNumberedEditor / HTMLPreview 自己监听 @EnvironmentObject
    }
}
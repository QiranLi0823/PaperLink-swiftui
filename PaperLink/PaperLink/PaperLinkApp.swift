//
//  PaperLinkApp.swift
//  PaperLink
//
//  Phase 1 Sprint 2+：@main + File 菜单（Open / Save / Save As / Rename）+ sidebar。
//

import SwiftUI

@main
struct PaperLinkApp: App {
    @StateObject private var document = PaperDocument()
    @StateObject private var sidebarState = SidebarState.shared
    @StateObject private var theme = ThemeManager.shared
    @State private var closeGuard: WindowCloseGuard?
    @State private var recentFiles: [(url: URL, path: String)] = []

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
                .environmentObject(sidebarState)
                .environmentObject(theme)
                .focusedSceneValue(\.sidebarState, sidebarState)
                .toolbar {
                    // sidebar 模式按钮：原生 Picker + segmented 样式（macOS 26 Liquid Glass）
                    ToolbarItemGroup(placement: .navigation) {
                        SidebarModeBar(activeMode: $sidebarState.activeMode, sidebarState: sidebarState)
                    }
                }
                .onAppear {
                    // 窗口首次出现时挂关闭守卫（未保存时弹确认对话框）
                    if closeGuard == nil, let window = NSApp.windows.first(where: { $0.isVisible }) {
                        closeGuard = WindowCloseGuard(document: document, window: window)
                    }
                    refreshRecent()
                }
                // Finder 双击 .pml 文件 / `open file.pml` 命令行 → 加载目标文件
                .onOpenURL { url in
                    document.open(url: url)
                }
                // Open Recent 列表变化 → 刷新菜单
                .onReceive(NotificationCenter.default.publisher(for: .paperLinkRecentChanged)) { _ in
                    refreshRecent()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            // File 菜单：替换默认的 New Item，加 Open / Save / Save As / Rename / Open Recent / Settings
            CommandGroup(replacing: .newItem) {
                Button("Open…") { openAction() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Save") { document.save() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!document.isDirty)
                Button("Save As…") { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Rename") { renameAction() }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                openRecentMenu
                Divider()
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    /// Open Recent 子菜单：动态列出最近 10 个 .pml 文件
    @ViewBuilder
    private var openRecentMenu: some View {
        Menu("Open Recent") {
            if recentFiles.isEmpty {
                Text("No Recent Files")
            } else {
                ForEach(Array(recentFiles.enumerated()), id: \.offset) { _, item in
                    Button(item.url.lastPathComponent) {
                        document.open(url: item.url)
                    }
                }
                Divider()
                Button("Clear Menu") {
                    PaperDocument.clearRecent()
                }
            }
        }
    }

    private func refreshRecent() {
        recentFiles = PaperDocument.recentFiles()
    }

    private func openAction() {
        ProjectManager.shared.openPanel { url in
            guard let url = url else { return }
            document.open(url: url)
        }
    }

    private func renameAction() {
        // 通过 NSApp 主窗口触发 ContentView 的重命名模式
        // 简化：用通知
        NotificationCenter.default.post(name: .paperLinkStartRename, object: nil)
    }
}

// FocusedValue 传递（备用）
extension FocusedValues {
    @Entry var sidebarState: SidebarState? = nil
}

/// macOS 26 sidebar 模式按钮组：去外框、悬浮式
///
/// 视觉语言：
///   - 完全无外框 / 无背景 / 无边框
///   - 每个按钮：未选中 = 次要色 / 选中 = accent color 透明度椭圆底
///   - hover = 极轻的灰底
///   - 整体融入 toolbar 背景
///
/// 点击行为：
///   - 当前已激活 → 收起（activeMode = nil）
///   - 当前别的模式 → 切换
///   - 当前收起 → 展开
struct SidebarModeBar: View {
    @Binding var activeMode: SidebarView.Mode?
    @ObservedObject var sidebarState: SidebarState

    var body: some View {
        HStack(spacing: 0) {
            segment(.project)
            segment(.figures)
            // 分隔
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 0.5, height: 14)
                .padding(.horizontal, 4)
            // Sprint 9：跟随光标 toggle（独立按钮，复用 segment 视觉）
            followCursorButton
        }
    }

    @ViewBuilder
    private func segment(_ mode: SidebarView.Mode) -> some View {
        let isActive = activeMode == mode

        Button {
            if activeMode == mode {
                activeMode = nil
            } else {
                activeMode = mode
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                    .frame(width: 22, height: 22)
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: 32, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode == .project ? "项目文件树" : "图片列表")
    }

    @ViewBuilder
    private var followCursorButton: some View {
        let active = sidebarState.followCursorMode
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                sidebarState.followCursorMode.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(active ? Color.accentColor.opacity(0.18) : Color.clear)
                    .frame(width: 22, height: 22)
                Image(systemName: "arrow.left.arrow.right.square")
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
            }
            .frame(width: 32, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("跟随光标（编辑器与预览同步滚动）")
    }
}

extension Notification.Name {
    static let paperLinkStartRename = Notification.Name("PaperLink.startRename")
    static let paperLinkOpenFile = Notification.Name("PaperLink.openFile")
    // Sprint 8.4 ⌘F 查找
    static let paperLinkFindQueryChanged = Notification.Name("PaperLink.findQueryChanged")
    static let paperLinkFindGotoMatch    = Notification.Name("PaperLink.findGotoMatch")
    static let paperLinkFindMatchCount   = Notification.Name("PaperLink.findMatchCount")
    static let paperLinkFindCurrentIndex = Notification.Name("PaperLink.findCurrentIndex")
    // Sprint 9 跟随光标
    static let paperLinkFollowCursorFraction = Notification.Name("PaperLink.followCursorFraction")
    // Sprint 9.7：editor → preview 用真实 DOM 锚点 (kind, index, progress)
    static let paperLinkFollowCursorAnchor = Notification.Name("PaperLink.followCursorAnchor")
    // Sprint 9.16：跟随光标开关 off → on 时，PreviewPaneContent 发出此通知，
    // Editor 端收到后用当前光标行主动算一次 anchor，让 preview 立即滚动
    static let paperLinkFollowCursorEnabled = Notification.Name("PaperLink.followCursorEnabled")
}
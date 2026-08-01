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
    @State private var closeGuard: WindowCloseGuard?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
                .environmentObject(sidebarState)
                .focusedSceneValue(\.sidebarState, sidebarState)
                .toolbar {
                    // sidebar 模式按钮：原生 Picker + segmented 样式（macOS 26 Liquid Glass）
                    ToolbarItemGroup(placement: .navigation) {
                        SidebarModeBar(activeMode: $sidebarState.activeMode)
                    }
                }
                .onAppear {
                    // 窗口首次出现时挂关闭守卫（未保存时弹确认对话框）
                    if closeGuard == nil, let window = NSApp.windows.first(where: { $0.isVisible }) {
                        closeGuard = WindowCloseGuard(document: document, window: window)
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            // File 菜单：替换默认的 New Item，加 Open / Save / Save As / Rename
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
            }
        }
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

    var body: some View {
        HStack(spacing: 0) {
            segment(.project)
            segment(.figures)
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
                // 选中态蓝色底（正圆 22pt，独立于按钮 hit area）
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                    .frame(width: 22, height: 22)
                // icon（按钮 hit area 是 32×22 椭圆）
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
}

extension Notification.Name {
    static let paperLinkStartRename = Notification.Name("PaperLink.startRename")
    static let paperLinkOpenFile = Notification.Name("PaperLink.openFile")
}
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
                .environmentObject(sidebarState)
                .focusedSceneValue(\.sidebarState, sidebarState)
                .toolbar {
                    // sidebar 模式按钮：原生 Picker + segmented 样式（macOS 26 Liquid Glass）
                    ToolbarItemGroup(placement: .navigation) {
                        SidebarModeBar(
                            activeMode: $sidebarState.activeMode,
                            onSameMode: {
                                sidebarState.toggleVisibility()
                            }
                        )
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

/// macOS 风 sidebar 模式 bar：原生 Picker + segmented 样式
/// macOS 26 自动用 Liquid Glass 滑动效果
struct SidebarModeBar: View {
    @Binding var activeMode: SidebarView.Mode?
    let onSameMode: () -> Void    // 再点同一个 → 收起 sidebar

    @State private var lastSelection: SidebarView.Mode?

    var body: some View {
        Picker(
            "Sidebar Mode",
            selection: Binding(
                get: { activeMode ?? .project },
                set: { newMode in
                    // 检测"再点同一个"
                    if newMode == lastSelection && activeMode == newMode {
                        onSameMode()
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeMode = newMode
                    }
                    lastSelection = newMode
                }
            )
        ) {
            ForEach(SidebarView.Mode.allCases) { mode in
                Image(systemName: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 90, height: 22)
    }
}

extension Notification.Name {
    static let paperLinkStartRename = Notification.Name("PaperLink.startRename")
    static let paperLinkOpenFile = Notification.Name("PaperLink.openFile")
}
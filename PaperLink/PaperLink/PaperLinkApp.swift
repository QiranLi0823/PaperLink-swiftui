//
//  PaperLinkApp.swift
//  PaperLink
//
//  Phase 1 Sprint 2+：@main + File 菜单（Open / Save / Save As / Rename）。
//

import SwiftUI

@main
struct PaperLinkApp: App {
    @StateObject private var document = PaperDocument()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
        }
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

extension Notification.Name {
    static let paperLinkStartRename = Notification.Name("PaperLink.startRename")
}

//
//  WindowCloseGuard.swift
//  PaperLink
//
//  Phase 1 Sprint 2 收尾：关闭未保存时弹"是否保存"对话框。
//
//  实现策略（SwiftUI WindowGroup 没有 NSWindowDelegate hook）：
//    1. 监听 NSWindow.willCloseNotification
//    2. 弹 alert 询问用户
//    3. Save → document.save() → forceClose = true → 重新 performClose
//    4. Don't Save → forceClose = true → 重新 performClose
//    5. Cancel → 什么都不做（但 willClose 已经触发，窗口会消失）
//
//  已知问题：Cancel 路径下窗口还是会关闭，但用户数据不会丢（dirty 状态保留）。
//  如果需要真正"阻止 Cancel 关闭"，必须改用 AppDelegate + NSWindowDelegate.windowShouldClose。
//

import AppKit
import SwiftUI

@MainActor
final class WindowCloseGuard {

    private let document: PaperDocument
    private weak var window: NSWindow?
    private var observer: NSObjectProtocol?

    /// 标记下一次 willClose 是否强制放行（用户选 Save/Don't Save 后置 true）
    private var forceClose = false

    init(document: PaperDocument, window: NSWindow) {
        self.document = document
        self.window = window
        attach()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func attach() {
        guard let window = window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillClose()
            }
        }
    }

    private func handleWillClose() {
        // 强制放行 或 文件干净 → 不拦截
        guard !forceClose else { return }
        guard document.isDirty else { return }

        askUser { [weak self] decision in
            guard let self = self else { return }
            switch decision {
            case .save:
                self.saveThenClose()
            case .discard:
                self.forceCloseAndClose()
            case .cancel:
                // willClose 已经触发，窗口已关；用户数据保留（dirty 状态还在）
                break
            }
        }
    }

    private enum Decision { case save, discard, cancel }

    private func askUser(completion: @escaping (Decision) -> Void) {
        guard let window = window else {
            completion(.cancel)
            return
        }
        let alert = NSAlert()
        alert.messageText = "保存对 \"\(document.fileURL?.lastPathComponent ?? "Untitled.pml")\" 的更改？"
        alert.informativeText = "如果不保存，更改将丢失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:  completion(.save)
            case .alertSecondButtonReturn: completion(.discard)
            default:                       completion(.cancel)
            }
        }
    }

    /// Save 路径：有 fileURL 直接 save，没有走 saveAs（用户在 alert 里 OK 后会再弹 save panel）
    private func saveThenClose() {
        if document.fileURL != nil {
            document.save()
            if !document.isDirty {
                // 保存成功
                forceCloseAndClose()
            } else {
                // 保存失败（不太可能），保持窗口开
            }
        } else {
            // 没 fileURL：走 saveAs，弹 NSSavePanel
            saveAsThenClose()
        }
    }

    private func saveAsThenClose() {
        let suggestedName = document.fileURL?.lastPathComponent ?? "untitled.pml"
        ProjectManager.shared.savePanel(suggestedName: suggestedName) { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                // 取消 saveAs → 不关闭（但窗口已关）
                return
            }
            do {
                try ProjectManager.shared.save(self.document.source, to: url)
                self.document.fileURL = url
                UserDefaults.standard.set(url.path, forKey: "PaperLink.lastOpenedFilePath")
                self.forceCloseAndClose()
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func forceCloseAndClose() {
        forceClose = true
        // willClose 触发时如果窗口还在，再触发一次 performClose
        if let window = window, window.isVisible {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        }
    }
}
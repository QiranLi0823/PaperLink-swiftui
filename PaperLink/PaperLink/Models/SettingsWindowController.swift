//
//  SettingsWindowController.swift
//  PaperLink
//
//  Phase 1 Settings：弹出 SettingsView 的 utility window（3:2 圆角卡片）。
//  单例 + 复用窗口，菜单再次点击 → 调出已有窗口。
//
//  视觉：NSVisualEffectView 做 macOS 真实"玻璃感"（vibrancy）底，
//        SwiftUI 内容（圆角 + 阴影）叠在上面。
//

import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    convenience init() {
        // 1. SwiftUI root view（圆角卡片 + 阴影）
        let rootView = SettingsView()
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        // 2. 玻璃材质底：.popover 是最通透的 vibrancy
        let glass = NSVisualEffectView()
        glass.material = .popover            // 玻璃 + 跟随系统
        glass.state = .active                 // 永远 active（窗口在最前时最亮）
        glass.blendingMode = .behindWindow    // 窗口后的内容透过来
        glass.translatesAutoresizingMaskIntoConstraints = false

        // 3. 把 hosting view 放进 glass 之上
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true  // 让 hosting 也被圆角裁剪（与玻璃圆角一致）
        container.addSubview(glass)
        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glass.topAnchor.constraint(equalTo: container.topAnchor),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // 4. 窗口：去掉系统背景，露出玻璃
        let style: NSWindow.StyleMask = [
            .titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel,
            .fullSizeContentView
        ]
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = "PaperLink Settings"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        // 透明背景 → 让 NSVisualEffectView 的玻璃透出来
        window.backgroundColor = .clear
        window.isOpaque = false
        // 圆角：SwiftUI 卡片会自己画圆角 + 阴影，这里不强制
        window.contentViewController = NSViewController()
        window.contentViewController?.view = container
        window.contentViewController?.view.wantsLayer = true
        window.center()

        self.init(window: window)
    }

    func show() {
        guard let window = self.window else { return }
        // 跟随当前主题（防止 ThemeManager 在 window 创建后才被切换）
        window.appearance = ThemeManager.shared.theme.nsAppearance
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
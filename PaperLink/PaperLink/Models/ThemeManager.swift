//
//  ThemeManager.swift
//  PaperLink
//
//  Phase 1 Settings：主题状态（system / dark / light）。
//  - 首次启动默认跟随 macOS 系统外观
//  - 切换显式主题时给所有窗口设 NSAppearance
//  - 选"跟随系统"时清掉 window.appearance，让窗口跟 NSApp 走系统
//

import SwiftUI
import AppKit
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .dark:   return "深色"
        case .light:  return "浅色"
        }
    }

    /// 显式 appearance（system 时返回 nil → 跟随系统）
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark:   return NSAppearance(named: .darkAqua)
        case .light:  return NSAppearance(named: .aqua)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "PaperLink.theme")
            applyToApp()
        }
    }

    private init() {
        // 首次启动默认跟随系统；之后读 UserDefaults
        if UserDefaults.standard.string(forKey: "PaperLink.theme") == nil {
            self.theme = .system
        } else {
            let stored = UserDefaults.standard.string(forKey: "PaperLink.theme") ?? AppTheme.system.rawValue
            self.theme = AppTheme(rawValue: stored) ?? .system
        }
        applyToApp()
    }

    /// 主题应用到整个 app
    private func applyToApp() {
        if let appearance = theme.nsAppearance {
            NSApp.appearance = appearance
            for window in NSApp.windows {
                window.appearance = appearance
            }
        } else {
            // 跟随系统：清掉所有 override
            NSApp.appearance = nil
            for window in NSApp.windows {
                window.appearance = nil
            }
        }
    }
}
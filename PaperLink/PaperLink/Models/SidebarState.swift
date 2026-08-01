//
//  SidebarState.swift
//  PaperLink
//
//  Phase 1 Sprint 3+: 全局 sidebar 状态。
//  让 toolbar 上的按钮能控制 sidebar 显示/模式选择。
//

import SwiftUI
import Combine

@MainActor
final class SidebarState: ObservableObject {
    static let shared = SidebarState()

    @Published var isVisible: Bool = true
    /// 当前展开的 mode（nil = 不展开）
    @Published var activeMode: SidebarView.Mode? = .project

    private init() {}

    func toggleVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible.toggle()
        }
    }

    func toggleMode(_ mode: SidebarView.Mode) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if activeMode == mode {
                // 再点同一个 → 整个 sidebar 收起
                isVisible = false
            } else {
                // 切到另一个 mode
                isVisible = true
                activeMode = mode
            }
        }
    }
}
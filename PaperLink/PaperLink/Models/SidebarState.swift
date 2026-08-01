//
//  SidebarState.swift
//  PaperLink
//
//  Phase 1 Sprint 3+: 全局 sidebar 状态。
//  toolbar 上的 Picker(.segmented) 控制 sidebar 显示/模式。
//
//  状态机（activeMode 二元状态）：
//    .project = (1, 0) 项目模式，sidebar 显示
//    .figures = (0, 1) 图片模式，sidebar 显示
//    nil      = (0, 0) sidebar 收起
//
//  规则：
//    - 点击当前激活模式 → 收起（nil）
//    - 点击另一个模式   → 切换到该模式
//    - 收起后点击任意模式 → 直接展开该模式
//

import SwiftUI
import Combine

@MainActor
final class SidebarState: ObservableObject {
    static let shared = SidebarState()

    /// 当前 sidebar 模式。nil = sidebar 收起
    @Published var activeMode: SidebarView.Mode? = .project

    /// Sprint 9：跟随光标模式（开 → 编辑器选区变化时，preview 同步滚动到对应位置）
    @Published var followCursorMode: Bool = false

    /// sidebar 是否可见（= activeMode != nil）
    var isVisible: Bool { activeMode != nil }

    private init() {}

    /// 点击 Picker 的某个 mode：
    ///   - 同一 mode 再点 → 收起（nil）
    ///   - 不同 mode → 切换
    func select(_ mode: SidebarView.Mode) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if activeMode == mode {
                // (1,0) → (0,0) 或 (0,1) → (0,0)
                activeMode = nil
            } else {
                // (0,0) → (1,0) 或 (0,1) → (1,0) 或 (1,0) → (0,1)
                activeMode = mode
            }
        }
    }
}
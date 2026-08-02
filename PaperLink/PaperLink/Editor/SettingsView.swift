//
//  SettingsView.swift
//  PaperLink
//
//  Phase 1 Settings：3:2 圆角卡片，左侧 sidebar（Preferences / About）+ 右侧内容面板。
//
//  视觉（macOS Big Sur+ System Settings 风格）：
//    - 整张卡片固定 720×480（3:2），圆角 16pt，悬浮阴影
//    - 关闭用 NSPanel 自带的 traffic-light close 按钮（位于窗口 titlebar）
//    - 左侧 200pt sidebar：半透明 material、选中态左侧 3pt accent 标记 + 高亮填充
//    - 右侧 520pt 面板：上分割线 + 大标题，segmented 主题切换 + 卡片式 About
//

import SwiftUI

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case preferences = "Preferences"
        case about       = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .preferences: return "slider.horizontal.3"
            case .about:       return "info.circle.fill"
            }
        }
    }

    @State private var section: Section = .preferences
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        // 悬浮 sidebar：缩进 + 圆角 + material，浮在卡片左半边
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .padding(.leading, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider().opacity(0)
            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 480)
        // 玻璃由 NSPanel 里的 NSVisualEffectView 提供（.popover vibrancy）
        // SwiftUI 这层只画圆角阴影 + 内容
        .background(Color.clear)
        .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 12)
    }

    // MARK: - 左侧 sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部小 logo + app 名（强化 branding）
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("PaperLink")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

            // 分组小标题
            Text("Settings")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            VStack(spacing: 2) {
                ForEach(Section.allCases) { s in
                    row(s)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // 底部版本号
            HStack {
                Spacer()
                Text("v0.4")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))  // 玻璃上极轻浮雕
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func row(_ s: Section) -> some View {
        let active = s == section
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                section = s
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: s.icon)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(s.rawValue)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(alignment: .leading) {
                // 左侧 2pt accent 高亮条
                RoundedRectangle(cornerRadius: 1)
                    .fill(active ? Color.accentColor : Color.clear)
                    .frame(width: 2, height: 14)
                    .offset(x: -1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // hover 轻底（active 已高亮就不动）
            if !active {
                // 简化：靠 SwiftUI 自带 hover 反馈
                _ = hovering
            }
        }
    }

    // MARK: - 右侧面板

    @ViewBuilder
    private var panel: some View {
        switch section {
        case .preferences:
            preferencesPanel
        case .about:
            aboutPanel
        }
    }

    // MARK: Preferences

    private var preferencesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 大标题区
            VStack(alignment: .leading, spacing: 4) {
                Text("Preferences")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("自定义 PaperLink 的外观与行为")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)
            .padding(.bottom, 18)
            .padding(.horizontal, 28)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 主题分组
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("主题", "选择编辑器配色，跟随系统或锁定")
                        themeSegmented
                    }

                    // 预留：未来扩展分组占位
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("编辑器", "即将推出")
                        Text("行号 / 高亮 / 自动换行 / 字体 等设置")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                .padding(28)
            }
        }
    }

    /// segmented 主题切换器：3 选 1，胶囊底，icon + 文字
    private var themeSegmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(AppTheme.allCases.enumerated()), id: \.element.id) { idx, t in
                themeSegmentButton(t)
                    .frame(maxWidth: .infinity)
                if idx < AppTheme.allCases.count - 1 {
                    Divider().opacity(0.3).frame(height: 18)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 1, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func themeSegmentButton(_ t: AppTheme) -> some View {
        let active = theme.theme == t
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                theme.theme = t
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: themeIcon(t))
                    .font(.system(size: 11, weight: .medium))
                Text(t.displayName)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(active
                          ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                          : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t.displayName)
    }

    private func themeIcon(_ t: AppTheme) -> String {
        switch t {
        case .system: return "circle.righthalf.filled"
        case .dark:   return "moon.fill"
        case .light:  return "sun.max.fill"
        }
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: About

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 大标题
            VStack(alignment: .leading, spacing: 4) {
                Text("About")
                    .font(.system(size: 22, weight: .semibold))
                Text("PaperLink 编辑器信息")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)
            .padding(.bottom, 18)
            .padding(.horizontal, 28)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // app 卡片
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.6)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 56, height: 56)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PaperLink")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Version 0.4 · macOS 14+")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    // 技术路线
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("技术路线", "构建 PaperLink 用到的核心栈")
                        techStackList
                    }

                    // 开发者
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("开发者", "反馈与建议")
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("ilnksight@163.com")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .padding(28)
            }
        }
    }

    private var techStackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            techRow(icon: "swift", color: .orange, title: "SwiftUI + AppKit 混合架构")
            divider()
            techRow(icon: "doc.text", color: .blue, title: "纯 Swift PaperML 解析器")
            divider()
            techRow(icon: "globe", color: .green, title: "WKWebView + KaTeX CDN")
            divider()
            techRow(icon: "lock.shield", color: .purple, title: "App Sandbox + 安全书签")
            divider()
            techRow(icon: "tag", color: .pink, title: "自定义 UTI com.paperlink.pml")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func techRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 5)
    }

    private func divider() -> some View {
        Divider().opacity(0.4).padding(.leading, 28)
    }
}
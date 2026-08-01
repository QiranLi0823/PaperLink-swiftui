//
//  SidebarView.swift
//  PaperLink
//
//  Phase 1 Sprint 3: 左侧导航栏。
//  两种模式：项目文件树 (ProjectNavigator) / 图片缩略图网格 (FiguresGrid)。
//  顶部 toolbar 切换模式 + 可整体 hide。
//

import SwiftUI
import AppKit

// MARK: - 主侧边栏

struct SidebarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case project = "项目"
        case figures = "图片"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .project: return "folder"
            case .figures: return "photo.on.rectangle"
            }
        }
    }

    @ObservedObject var treeManager: ProjectTreeManager
    @Binding var activeMode: Mode?
    let currentFileURL: URL?

    var body: some View {
        // 外层 padding 让圆角面板浮在窗口背景上
        VStack(spacing: 0) {
            sidebarPanel
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 整个侧边栏：一个大圆角面板
    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // 内容区（用 VStack 不用 ZStack，避免 transition 计算错位）
            if let activeMode = activeMode {
                Group {
                    switch activeMode {
                    case .project:
                        ProjectNavigatorView(
                            root: treeManager.root,
                            currentFileURL: currentFileURL,
                            onSelect: { url in
                                NotificationCenter.default.post(
                                    name: .paperLinkOpenFile,
                                    object: url
                                )
                            }
                        )
                    case .figures:
                        FiguresGridView(figures: treeManager.figures)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // activeMode == nil 时的占位（避免完全空白）
                VStack {
                    Spacer()
                    Text("点击上方图标查看内容")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 底部 Filter 输入条
            filterBar
        }
        .background(
            // 用纯色背景替代 .regularMaterial（避免在深色背景下变黑）
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
        )
    }

    /// 底部 Filter 输入条
    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text("Filter")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button {
                // 占位：搜索激活
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
        .padding(8)
    }
}

// MARK: - 项目文件树

struct ProjectNavigatorView: View {
    let root: FileNode?
    let currentFileURL: URL?
    let onSelect: (URL) -> Void

    /// 展开状态：持有在父视图，避免递归 View struct + @State 抖动
    @State private var expanded: Set<URL> = []

    var body: some View {
        if let root = root {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(flatten(root, depth: 0, isExpanded: isExpanded(_:))) { row in
                        FileRow(
                            node: row.node,
                            depth: row.depth,
                            isExpanded: row.isExpanded,
                            currentFileURL: currentFileURL,
                            onToggle: { toggle(root: row.node) },
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                // 默认展开根目录
                if expanded.isEmpty {
                    expanded.insert(root.id)
                }
            }
        } else {
            emptyState
        }
    }

    private func isExpanded(_ node: FileNode) -> Bool {
        expanded.contains(node.id)
    }

    private func toggle(root node: FileNode) {
        if expanded.contains(node.id) {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }

    /// 把递归的 FileNode 树展平成带深度的行数组
    /// （非递归 View struct：SwiftUI 在 View body 里递归创建 struct 会触发 "Publishing changes" 死循环）
    private func flatten(_ node: FileNode, depth: Int, isExpanded: (FileNode) -> Bool) -> [FlatRow] {
        var out: [FlatRow] = [FlatRow(node: node, depth: depth, isExpanded: isExpanded(node))]
        if node.isDirectory && isExpanded(node) {
            for child in node.children {
                out.append(contentsOf: flatten(child, depth: depth + 1, isExpanded: isExpanded))
            }
        }
        return out
    }

    private struct FlatRow: Identifiable {
        let node: FileNode
        let depth: Int
        let isExpanded: Bool
        var id: URL { node.id }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("未打开文件")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("打开 .pml 后会显示所在目录")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

/// 单行：扁平（非递归 View struct，安全）
private struct FileRow: View {
    let node: FileNode
    let depth: Int
    let isExpanded: Bool
    let currentFileURL: URL?
    let onToggle: () -> Void
    let onSelect: (URL) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 0) {
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }

                Image(systemName: iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
                    .frame(width: 18, height: 16)

                Text(node.name)
                    .font(.system(size: 12, design: node.isPML ? .monospaced : .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .padding(.leading, CGFloat(depth) * 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.gray.opacity(0.12)
        }
        return Color.clear
    }

    private var isSelected: Bool {
        currentFileURL?.standardizedFileURL == node.url.standardizedFileURL
    }

    private var iconName: String {
        if node.isDirectory { return isExpanded ? "folder.fill" : "folder" }
        if node.isPML { return "doc.text" }
        if node.isImage { return "photo" }
        return "doc"
    }

    private var iconColor: Color {
        if node.isDirectory { return Color(nsColor: .systemBlue) }
        if node.isPML { return Color(nsColor: .labelColor) }
        if node.isImage { return Color(nsColor: .systemPurple) }
        return Color(nsColor: .secondaryLabelColor)
    }

    private func handleTap() {
        if node.isDirectory {
            onToggle()
        } else {
            onSelect(node.url)
        }
    }
}

// MARK: - 图片文件列表

struct FiguresGridView: View {
    let figures: [URL]

    var body: some View {
        if figures.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(figures, id: \.self) { url in
                        FigureRow(url: url)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("暂无图片")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("把图片放到 figures/ 目录")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

/// 单行：图标 + 文件名（无缩略图，避免卡顿）
private struct FigureRow: View {
    let url: URL
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemPurple))
                .frame(width: 18, height: 16)

            Text(url.lastPathComponent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Rectangle()
                .fill(isHovered ? Color.gray.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .help(url.path)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "photo"
        case "gif": return "photo.stack"
        case "pdf": return "doc.richtext"
        default: return "photo"
        }
    }
}
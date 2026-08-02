//
//  FindBar.swift
//  PaperLink
//
//  Phase 1 Sprint 8.4：⌘F 查找条。悬浮在编辑器顶部，含 query + prev/next + 命中数。
//

import SwiftUI

struct FindBar: View {
    @Binding var query: String
    @Binding var matchCount: Int
    @Binding var currentIndex: Int   // 0-based
    var onPrev: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // 放大镜 icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            // 输入框
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($focused)
                .onSubmit { onNext() }
                .frame(width: 180)

            // 命中数
            if !query.isEmpty {
                Text(matchCount == 0 ? "No results" : "\(currentIndex + 1) of \(matchCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }

            // 按钮组
            Button(action: onPrev) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.plain)
            .help("上一个 (⇧⌘G)")
            .disabled(matchCount == 0)
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.plain)
            .help("下一个 (⌘G)")
            .disabled(matchCount == 0)
            .keyboardShortcut("g", modifiers: [.command])

            // 关闭
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.gray.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("关闭 (Esc)")
            .keyboardShortcut(.cancelAction)  // ESC
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 2)
        .onAppear { focused = true }
    }
}
//
//  LineNumberedEditor.swift
//  PaperLink
//
//  Phase 1 Sprint 1+: 带行号 + 错误高亮的编辑器。
//  NSTextView 包装 + 自定义左侧 gutter NSView（画行号 + 错误行红底）。
//

import SwiftUI
import AppKit

// MARK: - SwiftUI View

struct LineNumberedEditor: NSViewRepresentable {
    @Binding var text: String
    let errors: [ParseError]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSView {
        // 容器：左边 gutter + 右边 textView
        let container = LineNumberContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return container }

        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.string = text
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = NSColor.controlAccentColor
        scrollView.hasVerticalRuler = false
        scrollView.hasHorizontalRuler = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let gutter = GutterView()
        gutter.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(gutter)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 32),

            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.textView = textView
        context.coordinator.gutter = gutter

        // Sprint 5：初始涂色
        Coordinator.applySyntaxHighlighting(to: textView)

        // 关键：让 gutter 监听 textView 的内容变化来刷新
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.refreshGutter),
            name: NSText.didChangeNotification,
            object: textView
        )

        // Sprint 5：监听 textView 内容变化，每次用户输入都重涂 @identifier
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.applyHighlight),
            name: NSText.didChangeNotification,
            object: textView
        )

        // 监听 frame 变化（包括滚动导致的 layoutManager 重布局）
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.refreshGutter),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.refreshGutter),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = container.subviews.compactMap({ $0 as? NSScrollView }).first,
              let textView = scrollView.documentView as? NSTextView,
              let gutter = context.coordinator.gutter else { return }

        if textView.string != text {
            // 外部 source 变化 → 整体替换 + 重涂语法高亮
            textView.string = text
            applySyntaxHighlighting(to: textView)
        }

        gutter.errorLines = Set(errors.map { $0.line })
        gutter.textView = textView
        gutter.scrollView = scrollView
        gutter.setNeedsDisplay(gutter.bounds)
    }

    /// 把所有 `@identifier` 涂成 accentColor（蓝色）。
    /// 用户敲击时 textView 自动处理单字符着色（不影响此函数），本函数只在外部 sync 时整体涂一遍。
    private func applySyntaxHighlighting(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        // 先清掉旧的 .foregroundColor（让默认色回来）
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: fullRange)

        // 涂 @identifier
        let pattern = #"@[A-Za-z_][A-Za-z0-9_]*"#
        var matchCount = 0
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
                guard let r = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: r)
                matchCount += 1
            }
        }
        storage.endEditing()
        print("[highlight] applied \(matchCount) @identifier tokens")
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        weak var gutter: GutterView?

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            refreshGutter()
        }

        @objc func refreshGutter() {
            guard let g = gutter, let tv = textView else { return }
            g.textView = tv
            g.scrollView = tv.enclosingScrollView
            g.setNeedsDisplay(g.bounds)
        }

        /// Sprint 5：用户输入后立刻重涂 @identifier
        @objc func applyHighlight() {
            guard let tv = textView else { return }
            Self.applySyntaxHighlighting(to: tv)
        }

        /// 把所有 `@identifier` 涂成 accentColor（蓝色），其余字符恢复默认 labelColor。
        /// （用 removeAttribute 会让 NSTextView fallback 到 hardcoded .black，所以一定要重新设回 labelColor）
        static func applySyntaxHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            let defaultColor = NSColor.labelColor

            storage.beginEditing()
            // 1. 全文档设为默认 labelColor（dark mode 下是白，light mode 下是黑）
            storage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

            // 2. 把 @identifier 覆盖成蓝色
            let pattern = #"@[A-Za-z_][A-Za-z0-9_]*"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
                    guard let r = match?.range else { return }
                    storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: r)
                }
            }
            storage.endEditing()
        }
    }
}

// MARK: - 容器

private class LineNumberContainerView: NSView {}

// MARK: - Gutter

/// 自定义 gutter：左侧画行号 + 错误行红底
class GutterView: NSView {
    var errorLines: Set<Int> = []
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    // 和 NSTextContainer 坐标系一致（底部原点），这样 layoutManager 给的 rect 可以直接用
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else {
            // 没有 textView 时只画背景
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            return
        }

        // 背景：略深于窗口底色
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        // 右边界线（更淡）
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 0.5, y: dirtyRect.origin.y, width: 0.5, height: dirtyRect.height).fill()

        let nsText = textStorage.string as NSString
        let totalChars = nsText.length
        let yOrigin = textView.textContainerInset.height

        // 文本 viewport 的 y 范围（考虑滚动）
        let documentVisibleRect = scrollView?.contentView.documentVisibleRect ?? textView.visibleRect
        // viewport 顶部在 textView 文档坐标系里的 y（左上原点）
        let viewportTopY = documentVisibleRect.origin.y
        let viewportBottomY = viewportTopY + documentVisibleRect.height

        // gutter 自己坐标转换：scrollView.contentView 滚动时 bounds.origin.y 变化
        // 这个值是 gutter 和 contentView 之间的相对偏移
        let scrollOffsetY = scrollView?.contentView.bounds.origin.y ?? 0

        var line = 1
        var charIndex = 0
        let endChar = totalChars

        while charIndex < endChar {
            let lineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))

            var actualGlyphRange = NSRange()
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: &actualGlyphRange)

            // 遍历这个字符 line 内的所有 visual line（软换行）
            var glyphIndex = lineGlyphRange.location
            while glyphIndex < NSMaxRange(lineGlyphRange) {
                var visualLineGlyphRange = NSRange()
                let visualLineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &visualLineGlyphRange,
                    withoutAdditionalLayout: true
                )
                let lineTopInTextView = visualLineRect.origin.y + yOrigin
                let gutterY = lineTopInTextView - scrollOffsetY
                let drawHeight = visualLineRect.height

                // 可见性判断
                guard gutterY + drawHeight >= dirtyRect.minY,
                      gutterY <= dirtyRect.maxY else {
                    glyphIndex = NSMaxRange(visualLineGlyphRange)
                    continue
                }

                // 错误行红底（每个 visual line 都画，让长段软换行也能视觉标记）
                if errorLines.contains(line) {
                    NSColor.systemRed.withAlphaComponent(0.10).setFill()
                    NSRect(x: 0, y: gutterY, width: bounds.width, height: drawHeight).fill()
                    NSColor.systemRed.setFill()
                    NSRect(x: 0, y: gutterY, width: 2, height: drawHeight).fill()
                }

                // 行号：只在字符 line 的第一个 visual line 画
                let isFirstVisualLine = (glyphIndex == lineGlyphRange.location)
                if isFirstVisualLine {
                    let lineNumString = "\(line)" as NSString
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: errorLines.contains(line)
                            ? NSColor.systemRed
                            : NSColor.tertiaryLabelColor
                    ]
                    let textSize = lineNumString.size(withAttributes: attrs)
                    let drawX = bounds.width - textSize.width - 6
                    lineNumString.draw(
                        at: NSPoint(x: drawX, y: gutterY + 1),
                        withAttributes: attrs
                    )
                }

                glyphIndex = NSMaxRange(visualLineGlyphRange)
            }

            charIndex = lineRange.location + lineRange.length
            line += 1
            if line > 10000 { break }
        }
    }
}
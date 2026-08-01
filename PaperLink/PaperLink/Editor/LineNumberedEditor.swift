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
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
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
            gutter.widthAnchor.constraint(equalToConstant: 44),

            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.textView = textView
        context.coordinator.gutter = gutter

        // 关键：让 gutter 监听 textView 的内容变化来刷新
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.refreshGutter),
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
            textView.string = text
        }

        gutter.errorLines = Set(errors.map { $0.line })
        gutter.textView = textView
        gutter.scrollView = scrollView
        gutter.setNeedsDisplay(gutter.bounds)
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

        // 背景
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        // 右边界线
        NSColor.gray.withAlphaComponent(0.3).setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.origin.y, width: 1, height: dirtyRect.height).fill()

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
            let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)

            // lineRect 在 textContainer 坐标系（也是 textView 坐标系，左上原点）
            let lineTopInTextView = lineRect.origin.y + yOrigin
            let lineBottomInTextView = lineTopInTextView + lineRect.height

            // gutter 也是左上原点（NSView 默认），所以直接平移
            // gutter y = 文本 y - 滚动偏移
            let gutterY = lineTopInTextView - scrollOffsetY
            let drawHeight = lineRect.height

            // 可见性判断
            guard gutterY + drawHeight >= dirtyRect.minY,
                  gutterY <= dirtyRect.maxY else {
                charIndex = lineRange.location + lineRange.length
                line += 1
                if line > 10000 { break }
                continue
            }

            // 错误行红底
            if errorLines.contains(line) {
                NSColor.red.withAlphaComponent(0.15).setFill()
                NSRect(x: 0, y: gutterY, width: bounds.width, height: drawHeight).fill()
            }

            // 行号
            let lineNumString = "\(line)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: errorLines.contains(line) ? NSColor.red : NSColor.secondaryLabelColor
            ]
            let textSize = lineNumString.size(withAttributes: attrs)
            let drawX = bounds.width - textSize.width - 6
            lineNumString.draw(at: NSPoint(x: drawX, y: gutterY + (drawHeight - textSize.height) / 2), withAttributes: attrs)

            charIndex = lineRange.location + lineRange.length
            line += 1
            if line > 10000 { break }
        }
    }
}
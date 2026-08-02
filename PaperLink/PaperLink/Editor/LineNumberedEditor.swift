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

        // Sprint 8.3：监听选区变化 → 更新 gutter.currentLine + 重绘
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        // Sprint 8.3：gutter 行号点击 → textView 跳到该行
        gutter.onClickLine = { [weak textView] line in
            guard let tv = textView else { return }
            LineNumberedEditor.jumpToLine(line, in: tv)
        }

        // Sprint 8.4：监听 FindBar 全局事件
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.findQueryChanged),
            name: .paperLinkFindQueryChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.findGotoMatch),
            name: .paperLinkFindGotoMatch,
            object: nil
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
        private var matchRanges: [NSRange] = []
        private var currentMatchIndex: Int = 0
        private var lastQuery: String = ""
        // Sprint 8 编译错修复：把 coordinator 标 main-actor，
        // 让 selectionChanged / recomputeMatchesAndHighlight 等闭包能合法访问 main-actor 隔离的方法
        // （如 document.open(url:) / NotificationCenter.post 等）

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            refreshGutter()
            recomputeMatchesAndHighlight()
        }

        /// Sprint 8.4：根据当前 searchQuery 重新计算所有匹配 + 涂背景 + 上报 count
        func recomputeMatchesAndHighlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            matchRanges.removeAll()
            currentMatchIndex = 0

            let q = lastQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty, let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: q), options: [.caseInsensitive]) else {
                NotificationCenter.default.post(name: .paperLinkFindMatchCount, object: nil, userInfo: ["count": 0])
                return
            }
            regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                guard let r = m?.range, r.length > 0 else { return }
                matchRanges.append(r)
            }
            let highlight = NSColor.findHighlightColor
            for r in matchRanges {
                storage.addAttribute(.backgroundColor, value: highlight, range: r)
            }
            NotificationCenter.default.post(name: .paperLinkFindMatchCount, object: nil, userInfo: ["count": matchRanges.count])
            if let first = matchRanges.first {
                tv.scrollRangeToVisible(first)
            }
        }

        /// Sprint 8.4：跳到下一个匹配（next = true）/ 上一个（next = false）
        func gotoMatch(next: Bool) {
            guard !matchRanges.isEmpty else { return }
            if next {
                currentMatchIndex = (currentMatchIndex + 1) % matchRanges.count
            } else {
                currentMatchIndex = (currentMatchIndex - 1 + matchRanges.count) % matchRanges.count
            }
            let r = matchRanges[currentMatchIndex]
            textView?.setSelectedRange(r)
            textView?.scrollRangeToVisible(r)
            textView?.showFindIndicator(for: r)
            NotificationCenter.default.post(name: .paperLinkFindCurrentIndex, object: nil, userInfo: ["index": currentMatchIndex])
        }

        /// Sprint 8.4：NotificationCenter 接 FindBar 的 query 变化
        @objc func findQueryChanged(_ note: Notification) {
            guard let q = note.userInfo?["query"] as? String else { return }
            lastQuery = q
            recomputeMatchesAndHighlight()
        }

        @objc func findGotoMatch(_ note: Notification) {
            let next = (note.userInfo?["next"] as? Bool) ?? true
            gotoMatch(next: next)
        }

        /// Sprint 8.2 自动闭合 + 智能缩进
        ///
        /// - `{` → 自动加 `}`，光标居中
        /// - `[` → 自动加 `]`
        /// - `(` → 自动加 `)`
        /// - `"` → 自动加 `"`，光标居中；再敲 `"` 时跳过
        /// - 回车：当前行尾是 `{` 且下一字符是 `}` → 自动插入一对换行 + 缩进，光标移到中间（多一对缩进）
        /// - 普通回车：保持当前行的行首缩进
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let str = replacementString, !str.isEmpty else { return true }

            // 单字符插入
            if str.count == 1 {
                let ch = str.first!
                let nsText = textView.string as NSString

                // 自动闭合：开字符 → 插入一对
                let pair: (Character, Character)?
                switch ch {
                case "{":  pair = ("{", "}")
                case "[":  pair = ("[", "]")
                case "(":  pair = ("(", ")")
                case "\"": pair = ("\"", "\"")
                default:   pair = nil
                }
                if let (open, close) = pair {
                    // 双引号 / 闭合键的跳过逻辑：紧跟着已有闭合字符 → 跳过插入只移光标
                    if open == close, affectedCharRange.location < nsText.length {
                        let nextChar = nsText.substring(with: NSRange(location: affectedCharRange.location, length: 1))
                        if nextChar == String(close) {
                            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                            return false
                        }
                    }
                    let combined = String(open) + String(close)
                    if textView.shouldChangeText(in: affectedCharRange, replacementString: combined) {
                        textView.replaceCharacters(in: affectedCharRange, with: combined)
                        textView.didChangeText()
                        textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                    }
                    return false
                }

                // 回车：括号内换行（当前行尾 `{` 紧跟下一字符 `}`）
                if ch == "\n" {
                    let prevCh: Character? = affectedCharRange.location > 0
                        ? Character(UnicodeScalar(nsText.character(at: affectedCharRange.location - 1))!)
                        : nil
                    let nextCh: Character? = affectedCharRange.location < nsText.length
                        ? Character(UnicodeScalar(nsText.character(at: affectedCharRange.location))!)
                        : nil
                    if prevCh == "{", nextCh == "}" {
                        // 当前行的行首缩进（连续空格/tab 数）
                        let lineRange = nsText.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                        let linePrefix = nsText.substring(with: NSRange(
                            location: lineRange.location,
                            length: max(0, affectedCharRange.location - lineRange.location)
                        ))
                        let indent = linePrefix.reversed().prefix(while: { $0 == " " || $0 == "\t" }).count
                        let indentStr = String(repeating: " ", count: indent)
                        // 多插一对缩进，让光标所在行更内
                        let insert = "\n" + indentStr + "  \n" + indentStr
                        if textView.shouldChangeText(in: affectedCharRange, replacementString: insert) {
                            textView.replaceCharacters(in: affectedCharRange, with: insert)
                            textView.didChangeText()
                            let cursorLoc = affectedCharRange.location + 1 + indentStr.count + 2
                            textView.setSelectedRange(NSRange(location: cursorLoc, length: 0))
                        }
                        return false
                    }

                    // 普通回车：保持行首缩进
                    let lineRange = nsText.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                    let linePrefix = nsText.substring(with: NSRange(
                        location: lineRange.location,
                        length: max(0, affectedCharRange.location - lineRange.location)
                    ))
                    let trailingWS = String(linePrefix.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
                    if !trailingWS.isEmpty {
                        let combined = "\n" + trailingWS
                        if textView.shouldChangeText(in: affectedCharRange, replacementString: combined) {
                            textView.replaceCharacters(in: affectedCharRange, with: combined)
                            textView.didChangeText()
                            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1 + trailingWS.count, length: 0))
                        }
                        return false
                    }
                }
            }
            return true
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

        /// Sprint 8.3：选区变化 → 计算当前行，更新 gutter 高亮
        @objc func selectionChanged() {
            guard let tv = textView, let g = gutter else { return }
            let nsText = tv.string as NSString
            let cursor = tv.selectedRange.location
            var line = 1
            var i = 0
            let scanEnd = min(cursor, nsText.length)
            while i < scanEnd {
                if nsText.character(at: i) == UInt16(UnicodeScalar("\n").value) {
                    line += 1
                }
                i += 1
            }
            g.currentLine = line
            g.setNeedsDisplay(g.bounds)
        }

        /// Sprint 8.1 多色语法高亮：
        ///   - 默认文字：labelColor（dark 白 / light 黑）
        ///   - @identifier：controlAccentColor（accent 蓝）
        ///   - "..." 字符串：systemGreen
        ///   - 数字：systemOrange
        ///   - // 注释：secondaryLabelColor
        ///
        /// 策略：先 reset 全文档到 labelColor；用 NSRegularExpression 匹配四种 token。
        /// @identifier 涂色时跳过字符串/注释内部范围（避免 `"author1@x.edu"` 里的 @ 被涂蓝）。
        static func applySyntaxHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            let defaultColor    = NSColor.labelColor
            let identifierColor = NSColor.controlAccentColor
            let stringColor     = NSColor.systemGreen
            let numberColor     = NSColor.systemOrange
            let commentColor    = NSColor.secondaryLabelColor

            // 1. 先扫描字符串 + 注释的 range，@identifier 涂色时要排除它们
            var excludedRanges: [NSRange] = []
            if let re = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    if let r = m?.range { excludedRanges.append(r) }
                }
            }
            if let re = try? NSRegularExpression(pattern: #"//[^\n]*"#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    if let r = m?.range { excludedRanges.append(r) }
                }
            }

            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

            // 数字（最先涂，最特异——避免被其他规则覆盖）
            if let re = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    guard let r = m?.range, r.length > 0 else { return }
                    storage.addAttribute(.foregroundColor, value: numberColor, range: r)
                }
            }
            // 注释
            if let re = try? NSRegularExpression(pattern: #"//[^\n]*"#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    guard let r = m?.range, r.length > 0 else { return }
                    storage.addAttribute(.foregroundColor, value: commentColor, range: r)
                }
            }
            // 字符串
            if let re = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    guard let r = m?.range, r.length > 0 else { return }
                    storage.addAttribute(.foregroundColor, value: stringColor, range: r)
                }
            }
            // @identifier（最后涂，跳过字符串/注释范围）
            if let re = try? NSRegularExpression(pattern: #"@[A-Za-z_][A-Za-z0-9_]*"#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    guard let r = m?.range, r.length > 0 else { return }
                    let start = r.location
                    if excludedRanges.contains(where: { NSLocationInRange(start, $0) }) {
                        return  // 落在字符串/注释里 → 不涂
                    }
                    storage.addAttribute(.foregroundColor, value: identifierColor, range: r)
                }
            }

            storage.endEditing()
        }
    }
}

// MARK: - 顶层静态方法

extension LineNumberedEditor {
    /// Sprint 8.3：跳到指定行（行号 1-based），gutter 点击时调用
    static func jumpToLine(_ line: Int, in textView: NSTextView) {
        let nsText = textView.string as NSString
        var current = 1
        var target = 0
        for i in 0..<nsText.length {
            if current == line { target = i; break }
            if nsText.character(at: i) == UInt16(UnicodeScalar("\n").value) {
                current += 1
            }
        }
        if current == line { target = nsText.length }  // 最后一行兜底
        var endIdx = target
        while endIdx < nsText.length, nsText.character(at: endIdx) != UInt16(UnicodeScalar("\n").value) {
            endIdx += 1
        }
        textView.setSelectedRange(NSRange(location: target, length: endIdx - target))
        textView.scrollRangeToVisible(NSRange(location: target, length: 0))
    }
}

// MARK: - 容器

private class LineNumberContainerView: NSView {}

// MARK: - Gutter

/// 自定义 gutter：左侧画行号 + 错误行红底 + 当前行 accent 高亮
class GutterView: NSView {
    var errorLines: Set<Int> = []
    var currentLine: Int? = nil     // Sprint 8.3 当前行（高亮左侧 2pt accent 条 + 极淡背景）
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    /// 点击 gutter 行号时触发（参数：点中的行号 1-based）
    var onClickLine: ((Int) -> Void)?

    // 和 NSTextContainer 坐标系一致（底部原点），这样 layoutManager 给的 rect 可以直接用
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let textView = textView else { return }
        let locationInGutter = convert(event.locationInWindow, from: nil)
        // 把 gutterY 还原成 textView 内的 y（加回 scrollOffsetY）
        let scrollOffsetY = scrollView?.contentView.bounds.origin.y ?? 0
        let textViewY = locationInGutter.y + scrollOffsetY - textView.textContainerInset.height
        // 用 layoutManager 反查（characterIndex(for:in:) 直接给 char index，不需要 glyph→char）
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            // textContainer 的坐标系 origin 在 textContainerInset 处，所以 y 直接用 textViewY
            let point = NSPoint(x: 0, y: textViewY)
            var fraction: CGFloat = 0
            let charIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
            let nsText = textView.string as NSString
            // charIndex → 行号
            var line = 1
            var i = 0
            let scanEnd = min(charIndex, nsText.length)
            while i < scanEnd {
                if nsText.character(at: i) == UInt16(UnicodeScalar("\n").value) {
                    line += 1
                }
                i += 1
            }
            onClickLine?(line)
        }
    }

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
                } else if currentLine == line {
                    // Sprint 8.3 当前行 accent 高亮（左侧 2pt + 极淡背景）
                    NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
                    NSRect(x: 0, y: gutterY, width: bounds.width, height: drawHeight).fill()
                    NSColor.controlAccentColor.setFill()
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

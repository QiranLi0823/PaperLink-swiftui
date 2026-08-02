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

        // Sprint 9.16：跟随光标 off → on 时主动触发一次（不等下一次 selectionChanged）
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.followCursorEnabled),
            name: .paperLinkFollowCursorEnabled,
            object: nil
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
            // Sprint 9.20：新文档/重载后编辑器"未交互"状态重置，
            // follow-cursor 不会因为旧的 selectedRange 误把 preview 滚到错位置
            context.coordinator.userHasInteracted = false
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
        // Sprint 9.20：编辑器是否曾被用户交互过（点击 / 输入 / 选区变化）。
        // 未交互时 selectedRange 是默认 0（文档开头），按这个算 anchor 会让
        // follow-cursor 主动刷新时把 preview 滚到顶部——用户期望不开。
        // 由 textDidBeginEditing / textViewDidChangeSelection 任一首次触发置 true。
        // updateNSView 也会在 document 变化时重置回 false。
        var userHasInteracted = false

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            refreshGutter()
            recomputeMatchesAndHighlight()
        }

        /// Sprint 9.20：用户首次编辑时翻转 userHasInteracted（兜底：selectionChanged 已能覆盖点击/选中场景，
        /// textDidBeginEditing 覆盖"用户只敲字不移动选区"的场景）
        func textDidBeginEditing(_ notification: Notification) {
            userHasInteracted = true
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
        /// - `%%` 块注释骨架（Sprint 9.19）：行首敲第二个 `%` 时自动展开成
        ///   ```
        ///   %%
        ///   \t
        ///   %%
        ///   ```
        ///   光标落在中间的 tab 缩进行
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let str = replacementString, !str.isEmpty else { return true }

            // Sprint 9.19 %% 块注释骨架：第二个 % 进入时触发
            // 条件：1) 输入是单个 %；2) 光标前一个字符是 %；3) 前一个 % 之前只有空白（行首）
            if str == "%", affectedCharRange.location >= 1 {
                let nsText = textView.string as NSString
                let prevIdx = affectedCharRange.location - 1
                let prevCh = Character(UnicodeScalar(nsText.character(at: prevIdx))!)
                if prevCh == "%" {
                    // 往前扫描，确认前一个 % 在行首（前面只有空白）
                    var j = prevIdx - 1
                    var atLineStart = true
                    while j >= 0 {
                        let c = Character(UnicodeScalar(nsText.character(at: j))!)
                        if c.isNewline { break }
                        if c != " " && c != "\t" { atLineStart = false; break }
                        j -= 1
                    }
                    if atLineStart {
                        // 展开：前一个 % 已在 loc-1，只需补齐 loc 之后的内容
                        // 插入字符：%\n\t\n%%  →  最终 loc-1..loc+5:  % % \n \t \n % %
                        //                                            ↑光标在 loc+3（\t 之后）
                        let insert = "%\n\t\n%%"
                        if textView.shouldChangeText(in: affectedCharRange, replacementString: insert) {
                            textView.replaceCharacters(in: affectedCharRange, with: insert)
                            textView.didChangeText()
                            let cursorLoc = affectedCharRange.location + 3
                            textView.setSelectedRange(NSRange(location: cursorLoc, length: 0))
                        }
                        return false
                    }
                }
            }

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

                    // 普通回车：保持当前行的行首缩进
                    // Sprint 9.19：行首有缩进 → 用 leadingWS（光标紧贴 tab 后也能继承，如块注释骨架中行）
                    // 行首无缩进但光标前有空白 → 回退到 trailingWS（保留旧行为）
                    let lineRange = nsText.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                    let linePrefix = nsText.substring(with: NSRange(
                        location: lineRange.location,
                        length: max(0, affectedCharRange.location - lineRange.location)
                    ))
                    let leadingWS = String(linePrefix.prefix(while: { $0 == " " || $0 == "\t" }))
                    let indent = leadingWS.isEmpty
                        ? String(linePrefix.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
                        : leadingWS
                    if !indent.isEmpty {
                        let combined = "\n" + indent
                        if textView.shouldChangeText(in: affectedCharRange, replacementString: combined) {
                            textView.replaceCharacters(in: affectedCharRange, with: combined)
                            textView.didChangeText()
                            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1 + indent.count, length: 0))
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
        /// Sprint 9.2：同时算光标在文档中的纵向 fraction（用 layoutManager 像素 y / 总像素高），
        /// 50ms debounce post 给 HTMLPreview 做滚动同步
        private var fractionDebounce: Timer?
        @objc func selectionChanged() {
            guard let tv = textView, let g = gutter else { return }
            // Sprint 9.20：选区变化 = 用户已与编辑器交互
            userHasInteracted = true
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

            // Sprint 9.2：fraction = 光标所在字符的 y / 文档总 y（layoutManager 坐标系）
            scheduleFractionPost()
        }

        /// Sprint 9.16：跟随光标 off → on 主动触发一次。
        /// 直接调 postFollowCursorFraction 复用现有 anchor 算 + notify 路径
        /// （不绕 50ms debounce，开关瞬间就要滚）。
        @objc func followCursorEnabled() {
            guard MainActor.assumeIsolated({ SidebarState.shared.followCursorMode }) else { return }
            fractionDebounce?.invalidate()
            fractionDebounce = nil
            postFollowCursorFraction()
        }

        private func scheduleFractionPost() {
            fractionDebounce?.invalidate()
            fractionDebounce = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.postFollowCursorFraction()
                }
            }
        }

        private func postFollowCursorFraction() {
            guard let tv = textView else { return }
            // Sprint 9.15：跟随光标按钮关闭时不发通知。deeper 的 Coordinator 也会
            // 再守一道，但源头先节流最干净。
            guard MainActor.assumeIsolated({ SidebarState.shared.followCursorMode }) else { return }
            // Sprint 9.20：编辑器从未被用户交互过时，selectedRange = 0（默认），
            // 此时算出的 anchor 是文档开头，开关按钮触发的主动刷新或 selectionChanged
            // 都不应让 preview 滚——等用户真点击 / 输入编辑器后再启动随动。
            guard userHasInteracted else { return }
            // Sprint 9.7：editor → preview 通过 (kind, index, progress) 锚点对齐，
            // preview 端用真实 DOM getBoundingClientRect() 拿高度（避免预估不准）。
            let nsText = tv.string as NSString
            let cursor = tv.selectedRange.location
            let cursorLine = lineNumber(at: cursor, in: nsText)
            let blocks = PaperMLLayout.cachedLayout(for: tv.string)
            if let anchor = PaperMLLayout.anchor(atLine: cursorLine, blocks: blocks) {
                print("[FollowCursor] line=\(cursorLine) → anchor kind=\(anchor.kind) index=\(anchor.index) progress=\(anchor.progress)")
                NotificationCenter.default.post(
                    name: .paperLinkFollowCursorAnchor,
                    object: nil,
                    userInfo: [
                        "kind": anchor.kind,
                        "index": anchor.index,
                        "progress": Double(anchor.progress)
                    ]
                )
            } else {
                print("[FollowCursor] line=\(cursorLine) → no anchor (blocks.count=\(blocks.count))")
            }

            // Sprint 9：跟随光标模式 → editor 自身把光标行滚到视窗中央
            // （点击 gutter、键盘跳行、普通移动光标都会触发 selectionChanged）
            if let layoutManager = tv.layoutManager,
               let textContainer = tv.textContainer {
                let totalHeight = layoutManager.usedRect(for: textContainer).height
                if totalHeight > 0 {
                    let charRange = NSRange(location: min(cursor, (tv.string as NSString).length), length: 0)
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
                    let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
                    let followMode = MainActor.assumeIsolated { SidebarState.shared.followCursorMode }
                    if followMode {
                        scrollEditorToCenter(lineRect: lineRect, totalHeight: totalHeight, in: tv)
                    }
                }
            }
        }

        /// 给定字符 offset，返回 1-based 行号（独立函数，避免和 selectionChanged 内的循环重复）
        private func lineNumber(at charIndex: Int, in nsText: NSString) -> Int {
            var line = 1
            let scanEnd = min(charIndex, nsText.length)
            for i in 0..<scanEnd {
                if nsText.character(at: i) == UInt16(UnicodeScalar("\n").value) {
                    line += 1
                }
            }
            return line
        }

        /// Sprint 9：把光标行滚到 textView 视窗纵向中央
        private func scrollEditorToCenter(lineRect: NSRect, totalHeight: CGFloat, in textView: NSTextView) {
            let visible = textView.visibleRect
            let viewportH = visible.height
            let lineMidY = lineRect.origin.y + lineRect.height / 2
            var newY = lineMidY - viewportH / 2
            let maxY = max(0, totalHeight - viewportH)
            if newY < 0 { newY = 0 }
            if newY > maxY { newY = maxY }
            let cur = textView.enclosingScrollView?.documentVisibleRect.origin ?? visible.origin
            let desired = NSPoint(x: cur.x, y: newY)
            // 已经在目标位置附近就跳过，避免抖动
            if abs(desired.y - cur.y) < 2 { return }
            textView.scroll(desired)
        }

        /// Sprint 8.1 多色语法高亮：
        ///   - 默认文字：labelColor（dark 白 / light 黑）
        ///   - @identifier：controlAccentColor（accent 蓝）
        ///   - "..." 字符串：systemGreen
        ///   - 数字：systemOrange
        ///   - // 注释：secondaryLabelColor
        ///     （Sprint 9.18 改成 `%` 行注释 + `%%...%%` 块注释）
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
            // Sprint 9.18：注释规则改成 `%`（行）+ `%%...%%`（块，跨行）
            // 行首 %：触发行注释到行尾；行首 %%：触发块注释到下一个 %%
            // 用正则同时识别两种，匹配范围用于 @identifier 涂色排除
            if let re = try? NSRegularExpression(pattern: #"%%[\s\S]*?%%"#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    if let r = m?.range { excludedRanges.append(r) }
                }
            }
            if let re = try? NSRegularExpression(pattern: #"(^|\n)\s*%[^\n]*"#, options: []) {
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
            // Sprint 9.18：涂色行首 `%` 和 `%%...%%` 块注释（secondaryLabelColor）
            if let re = try? NSRegularExpression(pattern: #"%%[\s\S]*?%%"#, options: []) {
                re.enumerateMatches(in: storage.string, options: [], range: fullRange) { m, _, _ in
                    guard let r = m?.range, r.length > 0 else { return }
                    storage.addAttribute(.foregroundColor, value: commentColor, range: r)
                }
            }
            if let re = try? NSRegularExpression(pattern: #"(^|\n)\s*%[^\n]*"#, options: []) {
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
    /// Sprint 8.3：跳到指定行（行号 1-based），gutter 点击时调用。
    /// Sprint 9：当 sidebarState.followCursorMode 开启时，把目标行滚到 editor 视窗中央。
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

        // Sprint 9：跟随光标模式 → 把目标行滚到视窗中央；否则保持"滚到可见"
        let followMode = MainActor.assumeIsolated { SidebarState.shared.followCursorMode }
        if followMode {
            scrollLineToCenter(line: line, charIndex: target, in: textView)
        } else {
            textView.scrollRangeToVisible(NSRange(location: target, length: 0))
        }
    }

    /// Sprint 9：把指定字符位置所在行滚动到 textView 视窗纵向中央
    private static func scrollLineToCenter(line: Int, charIndex: Int, in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let used = layoutManager.usedRect(for: textContainer)
        guard used.height > 0 else { return }

        // 取目标字符的 line fragment rect
        let charRange = NSRange(location: min(charIndex, (textView.string as NSString).length), length: 0)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location,
                                                       effectiveRange: nil,
                                                       withoutAdditionalLayout: true)
        let lineMidY = lineRect.origin.y + lineRect.height / 2
        let visible = textView.visibleRect
        let viewportH = visible.height
        // 让该行中点落在视窗中央：newOrigin.y = lineMidY - viewportH/2
        var newY = lineMidY - viewportH / 2
        let maxY = max(0, used.height - viewportH)
        if newY < 0 { newY = 0 }
        if newY > maxY { newY = maxY }

        // 当前 origin.x 保持
        let cur = textView.enclosingScrollView?.documentVisibleRect.origin ?? visible.origin
        let newOrigin = NSPoint(x: cur.x, y: newY)
        textView.scroll(newOrigin)
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

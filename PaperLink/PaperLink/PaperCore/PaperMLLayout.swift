//
//  PaperMLLayout.swift
//  PaperLink
//
//  Sprint 9.6：把 PaperML source 切分成"渲染层"的 block，每个 block 带预估渲染像素高。
// 用途：把 editor 的"源文件光标行"映射到 preview 的"渲染后像素 fraction"，
//       解决「源文件 @figure 5 行 ↔ 渲染图 500px」这种比例不对应问题。
//
// 策略：
//   1. 扫一遍 source，识别 @title/@abstract/@section/@subsection/@figure/@table 等顶层块，
//      记录 startLine/endLine/kind。
//   2. 每种 block 用一个固定预估渲染高 + body 内 @paragraph/@equation 等行数加权。
//   3. 给定光标行 → 二分查找属于哪个 block → 算 (累计 y + 当前 block 内 y) / 总 y。
//
// 这套预估值是经验近似，跟 HTMLRenderer 的 CSS 实际像素会有偏差；
// 关键是把 source line 比例 → rendered pixel 比例，对齐到 JS 端 scrollToFraction 的语义。
//

import Foundation

enum PaperMLLayout {

    /// 单个布局块的"语义 + 像素高"
    struct Block {
        let startLine: Int        // 1-based，包含
        let endLine: Int          // 1-based，包含
        let kind: Kind
        let renderedHeight: CGFloat
        /// Sprint 9.7：同 kind 内的出现次序（与 HTMLRenderer 端 data-block-index 对齐）
        let indexInKind: Int
    }

    /// Sprint 9.7：editor → preview 对齐用的轻量锚点
    struct Anchor {
        let kind: String   // "title" / "abstract" / "section" / "subsection" / "figure" / "table" / "paragraph" / "equation"
        let index: Int
        /// 当前光标行在 block 内的纵向进度 [0, 1]
        let progress: CGFloat
    }

    enum Kind {
        case title           // @title{...} 含 @author/@footnote
        case abstractBlock   // @abstract{...}
        case section         // @section Title
        case subsection      // @subsection Subtitle
        case figure          // @figure{...}
        case table           // @table{...}
        case equation        // @equation 顶层
        case paragraph       // 正文段落（无 @ 包裹的 plain text）
        case unknown         // 兜底
    }

    // MARK: - 预估渲染像素高（按 HTMLRenderer 的 CSS 实测近似）

    /// 文本每行 ≈ 28px（含 line-height 1.7 × 16px font）
    private static let kLineHeight: CGFloat = 28

    /// @title block（含 @author 列表）：title ~32px + authors ~24px × N + footnote ~18px
    private static func titleHeight() -> CGFloat { 160 }

    /// @abstract block：圆角框 padding 24 + heading 32 + 关键词 24 + 段落 N × 28
    private static func abstractHeight(textLineCount: Int) -> CGFloat {
        return 110 + CGFloat(textLineCount) * kLineHeight
    }

    /// @section 标题
    private static let sectionHeaderHeight: CGFloat = 60

    /// @subsection 标题
    private static let subsectionHeaderHeight: CGFloat = 50

    /// @figure：caption + label 60 + 图本身 400（占大头）
    private static let figureHeight: CGFloat = 460

    /// @table：caption + label 60 + rows × 32
    private static func tableHeight(rows: Int) -> CGFloat {
        return 60 + CGFloat(max(rows, 1)) * 32
    }

    /// @equation 顶层（独立行）：display 模式 ~60px
    private static let equationHeight: CGFloat = 60

    // MARK: - 切分 source → [Block]

    /// 把 source 切成布局块。粗略扫顶层 + 顶层内的 @figure/@table/@equation。
    static func layout(_ source: String) -> [Block] {
        var blocks: [Block] = []
        // Sprint 9.18：先去掉 `%` 注释（行 + 块），注释内容被替换成空格但行号保持不变
        let stripped = PaperMLParser.stripComments(source)
        let lines = stripped.components(separatedBy: "\n")
        var i = 0
        var counter = KindCounter()

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行 / 注释：跳过（不占渲染空间）
            // Sprint 9.18：注释符号改成 `%`（行）+ `%%`（块首）
            // 跨行块注释由 PaperMLParser.stripComments 在 layout 入口处统一去掉
            if trimmed.isEmpty || trimmed.hasPrefix("%") {
                i += 1
                continue
            }

            // 顶层块
            if trimmed.hasPrefix("@title") && trimmed.contains("{") {
                let endLine = blockEndByNextHeader(startIdx: i, lines: lines, kind: .title)
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: endLine,
                    kind: .title,
                    renderedHeight: titleHeight(),
                    indexInKind: counter.next(.title)
                ))
                i = endLine  // endLine (1-based) → 0-based = endLine - 1 → next start = endLine (0-based) = endLine + 1 (1-based)
                continue
            }

            if trimmed.hasPrefix("@abstract") && trimmed.contains("{") {
                let endLine = blockEndByNextHeader(startIdx: i, lines: lines, kind: .abstractBlock)
                let bodyLines = max(1, endLine - i)
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: endLine,
                    kind: .abstractBlock,
                    renderedHeight: abstractHeight(textLineCount: bodyLines),
                    indexInKind: counter.next(.abstractBlock)
                ))
                i = endLine
                continue
            }

            if isTopLevelHeader(trimmed, keyword: "section") {
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: i + 1,
                    kind: .section,
                    renderedHeight: sectionHeaderHeight,
                    indexInKind: counter.next(.section)
                ))
                i += 1
                continue
            }

            if isTopLevelHeader(trimmed, keyword: "subsection") {
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: i + 1,
                    kind: .subsection,
                    renderedHeight: subsectionHeaderHeight,
                    indexInKind: counter.next(.subsection)
                ))
                i += 1
                continue
            }

            // @figure / @table：开闭 brace 在自身块内。用 scanBracedBlock 算真实 endLine，
            // 避免被"下一个 top-level header"过早吃掉（L115 等紧跟 paragraph 会被吞）。
            // Sprint 9.13：bracedBlock 必须能匹配大括号嵌套（@rows = [[..], [..]] 等）。
            if trimmed.hasPrefix("@figure") && trimmed.contains("{") {
                let (endLine, _) = scanBracedBlock(lines: lines, startIdx: i)
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: endLine,
                    kind: .figure,
                    renderedHeight: figureHeight,
                    indexInKind: counter.next(.figure)
                ))
                i = endLine
                continue
            }

            if trimmed.hasPrefix("@table") && trimmed.contains("{") {
                let (endLine, _) = scanBracedBlock(lines: lines, startIdx: i)
                let rows = countTableRowsInRange(startIdx: i, endIdx: endLine - 1, lines: lines)
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: endLine,
                    kind: .table,
                    renderedHeight: tableHeight(rows: rows),
                    indexInKind: counter.next(.table)
                ))
                i = endLine
                continue
            }

            if trimmed.hasPrefix("@equation") {
                if trimmed.contains("{") {
                    let (endLine, _) = scanBracedBlock(lines: lines, startIdx: i)
                    blocks.append(Block(
                        startLine: i + 1,
                        endLine: endLine,
                        kind: .equation,
                        renderedHeight: equationHeight,
                        indexInKind: counter.next(.equation)
                    ))
                    i = endLine
                    continue
                }
                // 无 brace 老写法
                var endLine = i
                var j = i + 1
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if t.hasPrefix("@") {
                        let head = String(t.split(separator: " ").first ?? Substring(t))
                        let knownSubfields = ["@content", "@label", "@caption", "@marker", "@name", "@affiliation", "@email", "@orcid", "@note", "@path", "@title", "@keywords", "@columns", "@rows", "@corresponding", "@author", "@footnote"]
                        if knownSubfields.contains(head) {
                            endLine = j - 1
                            break
                        }
                        endLine = j - 1
                        break
                    }
                    endLine = j
                    j += 1
                }
                blocks.append(Block(
                    startLine: i + 1,
                    endLine: endLine,
                    kind: .equation,
                    renderedHeight: equationHeight,
                    indexInKind: counter.next(.equation)
                ))
                i = endLine + 1
                continue
            }

            // 顶层正文段落（endLine 用 1-based，与 startLine = i+1 对齐）
            var endLine = i + 1   // 1-based 起始行（单行 paragraph 时）
            var j = i + 1
            while j < lines.count {
                let t = lines[j].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if isTopLevelHeader(t, keyword: "title") || isTopLevelHeader(t, keyword: "abstract") ||
                   isTopLevelHeader(t, keyword: "section") || isTopLevelHeader(t, keyword: "subsection") ||
                   isTopLevelHeader(t, keyword: "figure") || isTopLevelHeader(t, keyword: "table") ||
                   isTopLevelHeader(t, keyword: "equation") {
                    break
                }
                endLine = j + 1  // 1-based
                j += 1
            }
            let lineCount = endLine - (i + 1) + 1
            blocks.append(Block(
                startLine: i + 1,
                endLine: endLine,
                kind: .paragraph,
                renderedHeight: CGFloat(max(lineCount, 1)) * kLineHeight,
                indexInKind: counter.next(.paragraph)
            ))
            i = endLine  // endLine 是 1-based，下一轮 0-based = endLine
        }

        return blocks
    }

    /// 严格区分顶层 vs 嵌套：trim 后必须以 `@keyword` 开头，且 `@` 前只能有空白。
    /// 关键：避免 "@subsection" 误匹配 "@section"；同时避免标题内的 "@author" 误判为顶层。
    private static func isTopLevelHeader(_ trimmed: String, keyword: String) -> Bool {
        guard trimmed.hasPrefix("@\(keyword)") else { return false }
        let after = trimmed.dropFirst(keyword.count + 1)  // 跳过 "@keyword"
        // 关键字后必须是空格 / 行尾 / { （即关键字边界）
        if after.isEmpty { return true }
        let first = after.first!
        return first == " " || first.isNewline || first == "{" || first == "\t"
    }

    /// Sprint 9.12：从 startIdx 开始的 brace 块的结束行（1-based）。
    /// 策略：**用"下一个顶层 header"作为边界**，绕开 brace 嵌套子块（@author/@footnote）干扰。
    /// 返回：本块的 1-based endLine（包含闭合 `}` 行）。
    private static func blockEndByNextHeader(startIdx: Int, lines: [String], kind: Kind) -> Int {
        // 找 > startIdx 的最小顶层 header 行（0-based）
        let nextHeaderIdx = (startIdx + 1..<lines.count).first { idx in
            isTopLevelHeaderLine(lines[idx])
        }
        if let nh = nextHeaderIdx {
            // 下一个 header 在 0-based nh（即 1-based nh+1），本块结束于它前一行（1-based = nh）
            return nh
        }
        return lines.count  // 兜底：1-based = lines.count（最后一行 = count - 1 + 1）
    }

    /// 判断 lines[idx] 是否为顶层 header（行首无 indent，且是 @title/@abstract/@section/@subsection）。
    private static func isTopLevelHeaderLine(_ line: String) -> Bool {
        if line.isEmpty { return false }
        // 行首必须是 @
        guard line.first == "@" else { return false }
        let after = line.dropFirst()
        return after.hasPrefix("title") || after.hasPrefix("abstract") ||
               after.hasPrefix("section") || after.hasPrefix("subsection")
    }

    /// Sprint 9.13：在 brace 块（@table / @figure / @abstract）结束后，紧接的 paragraph 段
    /// 由外层 while 循环自动识别（该行不以 @ 开头 → 走顶层 paragraph 路径）。
    /// 不再需要单独的 scanParagraphAfterBraceBlock 钩子。

    /// Sprint 9.7：给定光标行 → 返回 (kind, index, progress) 锚点
    /// Sprint 9.11：progress 固定为 0.5（块中央），让 preview 把块纵向中点对齐到视窗中央。
    /// 行级偏移没用 —— editor 单行 vs preview 渲染行高度差异大，行级对齐不可靠；
    /// 块中央对齐更稳定（每个语义块都是 editor 端一个完整块 + preview 端一个真实节点）。
    /// Sprint 9.12：line 不在任何 block 时，优先 fallback 到"前一个 block"（基于 startLine 搜），
    /// 而不是 `blocks.last` —— 因为末尾段落会误导 preview 滚到底。
    static func anchor(atLine line: Int, blocks: [Block]) -> Anchor? {
        // 1. 精确命中：line ∈ [startLine, endLine]
        for block in blocks {
            if line >= block.startLine && line <= block.endLine {
                // 行级 progress：让 preview 滚到 block 内该行对应的位置
                let span = max(block.endLine - block.startLine, 1)
                let progress = CGFloat(max(0, min(span, line - block.startLine))) / CGFloat(span)
                return Anchor(
                    kind: kindString(block.kind),
                    index: block.indexInKind,
                    progress: progress
                )
            }
        }
        // 2. 行在第一个 block 之前 → 用第一个块起始
        if let first = blocks.first, line < first.startLine {
            return Anchor(kind: kindString(first.kind), index: first.indexInKind, progress: 0)
        }
        // 3. 行在最后一个 block 之后 → 用最后一个块末尾
        if let last = blocks.last, line > last.endLine {
            return Anchor(kind: kindString(last.kind), index: last.indexInKind, progress: 1)
        }
        // 4. 找不到 → 兜底：最近的前一个 block，用 progress=1（块末尾）
        //    空行 / 边界行 → 停在 prev block 末尾，与下一行 block 中央自然衔接
        var prev: Block? = nil
        for block in blocks {
            if block.startLine > line { break }
            prev = block
        }
        if let p = prev {
            return Anchor(kind: kindString(p.kind), index: p.indexInKind, progress: 1)
        }
        return nil
    }

    private static func kindString(_ kind: Kind) -> String {
        switch kind {
        case .title: return "title"
        case .abstractBlock: return "abstract"
        case .section: return "section"
        case .subsection: return "subsection"
        case .figure: return "figure"
        case .table: return "table"
        case .paragraph: return "paragraph"
        case .equation: return "equation"
        case .unknown: return "unknown"
        }
    }

    /// 每种 kind 单独的计数器
    private struct KindCounter {
        var title = 0, abstractBlock = 0, section = 0, subsection = 0
        var figure = 0, table = 0, paragraph = 0, equation = 0
        mutating func next(_ k: Kind) -> Int {
            switch k {
            case .title: let v = title; title += 1; return v
            case .abstractBlock: let v = abstractBlock; abstractBlock += 1; return v
            case .section: let v = section; section += 1; return v
            case .subsection: let v = subsection; subsection += 1; return v
            case .figure: let v = figure; figure += 1; return v
            case .table: let v = table; table += 1; return v
            case .paragraph: let v = paragraph; paragraph += 1; return v
            case .equation: let v = equation; equation += 1; return v
            case .unknown: return 0
            }
        }
    }

    /// 给定光标行（1-based）→ fraction ∈ [0, 1]
    /// 同一 block 内按"行偏移 / block 行数"做线性插值。
    static func fraction(atLine line: Int, blocks: [Block]) -> CGFloat {
        guard !blocks.isEmpty else { return 0 }
        let totalHeight = blocks.reduce(0) { $0 + $1.renderedHeight }
        guard totalHeight > 0 else { return 0 }

        var accumulated: CGFloat = 0
        for block in blocks {
            if line >= block.startLine && line <= block.endLine {
                // 在此 block 内：累加到 block 起点的 y + 当前行在 block 内的偏移
                let lineCount = block.endLine - block.startLine + 1
                let progress = lineCount > 0
                    ? CGFloat(line - block.startLine) / CGFloat(lineCount)
                    : 0
                return max(0, min(1, (accumulated + progress * block.renderedHeight) / totalHeight))
            }
            accumulated += block.renderedHeight
            if line < block.startLine { break }  // 早停
        }
        return line < blocks.first?.startLine ?? 0 ? 0 : 1
    }

    /// 缓存：在 LineNumberedEditor 里重复 parse 同一 source 很贵（每次 selectionChanged 都算）。
    /// 用 (source.hash, source.length) 做 key 缓存 blocks。
    static func cachedLayout(for source: String) -> [Block] {
        let key = "\(source.hashValue)-\(source.count)"
        if let cached = _cache.value, cached.key == key {
            return cached.blocks
        }
        let blocks = layout(source)
        _cache.value = (key, blocks)
        return blocks
    }

    private static let _cache = Cache()
    private final class Cache {
        var value: (key: String, blocks: [Block])?
    }

    // MARK: - 辅助

    /// 扫描一个 `@xxx{...}` 块（顶层或 @title 内层），返回 endLine（1-based，包含闭合 `}` 行）。
    /// 假定第 idx 行（0-based）以 `@xxx{` 起始。
    /// **重要**：跳过 LaTeX 转义 `\{` `\}`（这些是字面字符，不是 brace）。
    private static func scanBracedBlock(lines: [String], startIdx: Int) -> (Int, Kind) {
        let kind: Kind
        let head = lines[startIdx].trimmingCharacters(in: .whitespaces)
        if head.hasPrefix("@title") { kind = .title }
        else if head.hasPrefix("@abstract") { kind = .abstractBlock }
        else if head.hasPrefix("@figure") { kind = .figure }
        else if head.hasPrefix("@table") { kind = .table }
        else { kind = .unknown }

        var depth = 0
        outer: for j in startIdx..<lines.count {
            let line = lines[j]
            var k = line.startIndex
            while k < line.endIndex {
                let c = line[k]
                if c == "\\" && line.index(after: k) < line.endIndex {
                    // 跳过 LaTeX 转义：\{ \} \\ \n \t 等
                    k = line.index(after: line.index(after: k))
                    continue
                }
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return (j + 1, kind) }
                }
                k = line.index(after: k)
            }
        }
        return (lines.count, kind)  // 未闭合 → 兜底到末尾
    }

    private static func scanBracedBlockWithBody(lines: [String], startIdx: Int)
        -> (endLine: Int, bodyLines: [String])
    {
        var depth = 0
        var body: [String] = []
        for j in startIdx..<lines.count {
            let line = lines[j]
            var lineContributesBody = false
            var k = line.startIndex
            while k < line.endIndex {
                let c = line[k]
                if c == "\\" && line.index(after: k) < line.endIndex {
                    // 跳过 LaTeX 转义
                    k = line.index(after: line.index(after: k))
                    continue
                }
                if c == "{" {
                    depth += 1
                    if depth >= 2 { lineContributesBody = true }
                } else if c == "}" {
                    depth -= 1
                    if depth == 0 { return (j + 1, body) }
                    lineContributesBody = true
                } else if depth >= 2 {
                    lineContributesBody = true
                }
                k = line.index(after: k)
            }
            if lineContributesBody { body.append(line) }
        }
        return (lines.count, body)
    }

    /// 统计 @table 内的数据行数（解析 `@rows = [[..], [..], ...]`）
    /// Sprint 9.13：接受显式 startIdx/endIdx（0-based，含闭端），避免被外层 brace 切割的 span 干扰。
    private static func countTableRowsInRange(startIdx: Int, endIdx: Int, lines: [String]) -> Int {
        let lo = max(0, startIdx)
        let hi = min(lines.count - 1, endIdx)
        guard lo <= hi else { return 1 }
        let joined = lines[lo...hi].joined(separator: "\n")
        guard let rowsRange = joined.range(of: "@rows") ?? joined.range(of: "rows") else {
            return 1
        }
        let after = joined[rowsRange.upperBound...]
        // 数嵌套 `[` 的层级 ≥2（外层 @rows=[]，内层每个数据行也是 []）
        var depth = 0
        var rows = 0
        for ch in after {
            if ch == "[" {
                depth += 1
                if depth == 2 { rows += 1 }
            } else if ch == "]" {
                depth -= 1
                if depth <= 0 && rows > 0 { break }
            }
        }
        return max(rows, 1)
    }
}
//
//  PaperMLParser.swift
//  PaperLink
//
//  PaperML 解析器 — 纯 Swift，零外部依赖。
//  返回 PaperMLDocument AST。
//
//  范围：覆盖 demo.pml 出现的所有结构（@title/@author/@footnote/@abstract/
//  @section/@subsection/@figure/@table/@equation/@cite/@ref）。
//  暂不处理：行内 $...$ 数学（按普通文本）。
//  错误策略：尽力解析，遇到无法识别的内容当 text 跳过。
//

import Foundation

enum PaperMLParser {

    /// 解析入口（Phase 1 Sprint 1：收集错误）
    /// 不破坏现有 parse(_:) API；老调用方继续可用。
    /// errors 是解析过程中识别的错误（@title 块没闭合、未识别的关键字等）
    static func parseWithErrors(_ source: String) -> ParseResult {
        let doc = parse(source)
        var errors: [ParseError] = []

        // 检查 1: @title 关键字出现但 parseTitle 失败
        if source.contains("@title"), doc.metadata.title == nil {
            if let titleStart = source.range(of: "@title") {
                let offset = source.distance(from: source.startIndex, to: titleStart.lowerBound)
                let pos = source.position(at: offset)
                errors.append(ParseError(
                    severity: .error,
                    line: pos.line,
                    column: pos.column,
                    message: "@title 块未能正确闭合（缺少 `}` 或内部语法错）"
                ))
            }
        }

        // 检查 2: @abstract 关键字出现但 parseAbstract 失败
        if source.contains("@abstract"), doc.metadata.abstract == nil {
            if let absStart = source.range(of: "@abstract") {
                let offset = source.distance(from: source.startIndex, to: absStart.lowerBound)
                let pos = source.position(at: offset)
                errors.append(ParseError(
                    severity: .error,
                    line: pos.line,
                    column: pos.column,
                    message: "@abstract 块未能正确闭合"
                ))
            }
        }

        // 检查 3: 顶层有 @author 但没在 @title 块内（孤立）
        if let authorRange = source.range(of: "@author") {
            let authorOffset = source.distance(from: source.startIndex, to: authorRange.lowerBound)
            if let titleRange = source.range(of: "@title"),
               titleRange.lowerBound < authorRange.lowerBound {
                if let titleEnd = findMatchingBrace(in: Substring(source), from: titleRange.upperBound) {
                    if titleEnd < authorRange.lowerBound {
                        let pos = source.position(at: authorOffset)
                        errors.append(ParseError(
                            severity: .error,
                            line: pos.line,
                            column: pos.column,
                            message: "@author 块应在 @title 块内嵌套，但检测到独立 @author"
                        ))
                    }
                }
            } else {
                let pos = source.position(at: authorOffset)
                errors.append(ParseError(
                    severity: .error,
                    line: pos.line,
                    column: pos.column,
                    message: "@author 块应在 @title 块内嵌套"
                ))
            }
        }

        // 检查 4: @footnote 未嵌装到 title
        if source.contains("@footnote") {
            if let title = doc.metadata.title, title.footnotes.isEmpty {
                if let fnRange = source.range(of: "@footnote") {
                    let offset = source.distance(from: source.startIndex, to: fnRange.lowerBound)
                    let pos = source.position(at: offset)
                    errors.append(ParseError(
                        severity: .warning,
                        line: pos.line,
                        column: pos.column,
                        message: "@footnote 块未能正确解析到 title 内"
                    ))
                }
            }
        }

        // 检查 5: 关键字拼错（如 @titl{、@sction{、@nam = "..."）— @ 开头不在已知列表
        // 已知关键字：块（用 {） + 行内（用 {key}）
        // 已知字段名（按块）：
        let knownKeywords = ["title", "abstract", "section", "subsection", "author", "footnote", "figure", "table", "equation", "cite", "ref"]
        let knownFields = ["title", "name", "affiliation", "email", "orcid", "note", "corresponding",
                           "marker", "label", "keywords", "caption", "columns", "rows",
                           "path", "content"]
        var searchStart = source.startIndex
        while searchStart < source.endIndex {
            guard let atRange = source.range(of: "@", range: searchStart..<source.endIndex) else { break }
            let afterAt = source.index(after: atRange.lowerBound)
            // 读关键字字符
            var kEnd = afterAt
            while kEnd < source.endIndex, source[kEnd].isLetter || source[kEnd] == "_" {
                kEnd = source.index(after: kEnd)
            }
            let keyword = String(source[afterAt..<kEnd])
            if !keyword.isEmpty && !knownKeywords.contains(keyword) && !knownFields.contains(keyword) {
                // 检查后续是 { (块拼错) 还是 = (字段拼错)
                let afterKw = source[kEnd...].drop(while: { $0.isWhitespace || $0.isNewline })
                let nextChar = afterKw.first
                let kind = (nextChar == "{") ? "块关键字" : (nextChar == "=") ? "字段" : "未知"
                if nextChar == "{" || nextChar == "=" {
                    let offset = source.distance(from: source.startIndex, to: atRange.lowerBound)
                    let pos = source.position(at: offset)
                    errors.append(ParseError(
                        severity: .error,
                        line: pos.line,
                        column: pos.column,
                        message: "未知的\(kind) @\(keyword)"
                    ))
                    break  // 只报第一个避免刷屏
                }
            }
            searchStart = kEnd
        }

        return ParseResult(document: doc, errors: errors)
    }

    /// 解析入口
    static func parse(_ source: String) -> PaperMLDocument {
        var doc = PaperMLDocument(metadata: .init(), sections: [])

        // 去掉 // 注释（在切分顶层之前）
        let stripped = stripComments(source)

        // 简单策略：扫描每个顶层块，按类型分发
        let blocks = splitTopLevel(stripped)

        // 第一遍：收集所有 section / subsection 为扁平 Section（含 level + blocks，children 为空）
        var flatSections: [Section] = []
        for block in blocks {
            switch block {
            case .title(let body):
                if let title = parseTitle(body) {
                    doc.metadata.title = title
                }
            case .abstract(let body):
                if let abs = parseAbstract(body) {
                    doc.metadata.abstract = abs
                }
            case .section(let title, let rest):
                flatSections.append(parseSection(title: title.trimmingCharacters(in: .whitespacesAndNewlines), level: .section, body: rest))
            case .subsection(let title, let rest):
                flatSections.append(parseSection(title: title.trimmingCharacters(in: .whitespacesAndNewlines), level: .subsection, body: rest))
            case .plainText:
                break
            }
        }

        // 第二遍：用栈把 subsection 嵌入最近的 .section 的 children
        doc.sections = nestSections(flatSections)

        return doc
    }

    /// 把扁平的 section 列表用栈嵌装：
    /// - .section 入栈
    /// - .subsection 嵌进栈顶 .section 的 children（不修改栈）
    /// - 如果栈为空（连续 subsection 或顶层 subsection），降级为独立 .section
    private static func nestSections(_ flat: [Section]) -> [Section] {
        var result: [Section] = []
        // 栈元素：(index_in_result, is_section)
        // 简化：只跟踪最近一个 .section 的引用
        var stack: [Section] = []

        for var sec in flat {
            switch sec.level {
            case .section:
                stack.append(sec)
                result.append(sec)
            case .subsection:
                if var top = stack.popLast() {
                    top.children.append(sec)
                    // 替换 result 末尾的元素
                    if let lastIdx = result.indices.last {
                        result[lastIdx] = top
                    }
                    stack.append(top)  // 继续让后续 subsection 嵌到同一个父
                } else {
                    // 没有父 section —— 降级为顶层 .section
                    sec.level = .section
                    result.append(sec)
                }
            }
        }
        return result
    }

    // MARK: - 顶层分块

    private enum TopBlock {
        case title(String)
        case abstract(String)
        case section(title: String, rest: String)
        case subsection(title: String, rest: String)
        case plainText(String)
    }

    /// 把源码按顶层块切分
    private static func splitTopLevel(_ source: String) -> [TopBlock] {
        var blocks: [TopBlock] = []
        var remaining = Substring(source)

        while !remaining.isEmpty {
            // 找下一个顶层关键字
            if let (kind, afterHeader) = scanHeader(remaining) {
                // 收集这块之前的所有空白/文本（丢弃）
                switch kind {
                case .title:
                    if let body = readBracedBody(afterHeader) {
                        blocks.append(.title(body.content))
                        remaining = body.remaining
                    } else { break }
                case .abstract:
                    if let body = readBracedBody(afterHeader) {
                        blocks.append(.abstract(body.content))
                        remaining = body.remaining
                    } else { break }
                case .section(let title):
                    let rest = readUntilNextHeader(afterHeader)
                    blocks.append(.section(title: title, rest: rest.content))
                    remaining = rest.remaining
                case .subsection(let title):
                    let rest = readUntilNextHeader(afterHeader)
                    blocks.append(.subsection(title: title, rest: rest.content))
                    remaining = rest.remaining
                }
            } else {
                blocks.append(.plainText(String(remaining)))
                break
            }
        }
        return blocks
    }

    private enum HeaderKind {
        case title
        case abstract
        case section(String)
        case subsection(String)
    }

    /// 在 source 开头扫描一个顶层关键字，返回类型和跳过关键字后的 Substring
    private static func scanHeader(_ source: Substring) -> (HeaderKind, Substring)? {
        let trimmed = source.drop(while: { $0.isWhitespace || $0.isNewline })
        if trimmed.isEmpty { return nil }

        // 必须以 @ 开头
        guard trimmed.first == "@" else { return nil }
        let afterAt = trimmed.dropFirst()

        // 关键字列表
        if afterAt.hasPrefix("title") {
            let rest = afterAt.dropFirst("title".count)
            return (.title, Substring(rest))
        }
        if afterAt.hasPrefix("abstract") {
            let rest = afterAt.dropFirst("abstract".count)
            return (.abstract, Substring(rest))
        }
        if afterAt.hasPrefix("subsection") {
            let after = afterAt.dropFirst("subsection".count)
            // 标题直到换行
            let title = readUntilNewline(after)
            return (.subsection(String(title.title)), title.remaining)
        }
        if afterAt.hasPrefix("section") {
            let after = afterAt.dropFirst("section".count)
            let title = readUntilNewline(after)
            return (.section(String(title.title)), title.remaining)
        }
        return nil
    }

    // MARK: - 读取辅助

    private struct ReadResult {
        var content: String
        var remaining: Substring
    }

    /// 从 source 当前位置开始读 {...} 块（匹配大括号）
    private static func readBracedBody(_ source: Substring) -> ReadResult? {
        // 跳过空白
        var i = source.startIndex
        while i < source.endIndex, source[i].isWhitespace {
            i = source.index(after: i)
        }
        guard i < source.endIndex, source[i] == "{" else { return nil }

        var depth = 0
        let start = i
        while i < source.endIndex {
            let ch = source[i]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let inner = source[source.index(after: start)..<i]
                    let afterEnd = source.index(after: i)
                    return ReadResult(content: String(inner), remaining: Substring(source[afterEnd...]))
                }
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// 读一行标题（@section Title 后面到换行的内容）
    private static func readUntilNewline(_ source: Substring) -> (title: Substring, remaining: Substring) {
        if let nl = source.firstIndex(where: { $0.isNewline }) {
            return (source[source.startIndex..<nl], source[source.index(after: nl)...])
        }
        return (source, Substring(""))
    }

    /// 读到一个下一个顶层关键字（@title/@abstract/@section/@subsection）为止
    private static func readUntilNextHeader(_ source: Substring) -> ReadResult {
        let headers = ["@title", "@abstract", "@section", "@subsection"]
        var earliest: Substring.Index? = nil
        for h in headers {
            if let r = source.range(of: h) {
                if earliest == nil || r.lowerBound < earliest! {
                    earliest = r.lowerBound
                }
            }
        }
        if let end = earliest {
            return ReadResult(content: String(source[source.startIndex..<end]), remaining: source[end...])
        }
        return ReadResult(content: String(source), remaining: Substring(""))
    }

    // MARK: - 解析各类型

    private static func parseTitle(_ body: String) -> TitleBlock? {
        // title 块内部结构：先有 `title = "..."`，然后若干 @author{...} / @footnote{...} 子块
        // 自己切分子块，因为 splitTopLevel 不识别 @author/@footnote 作为顶层关键字
        var title = ""
        var authors: [Author] = []
        var footnotes: [Footnote] = []

        // 1. 提取 title = "..." 字段
        let titleKV = parseKeyValues(body)
        title = titleKV["title"] ?? ""

        // 2. 切分 @author / @footnote 子块
        let subBlocks = splitAuthorFootnote(body)
        for sub in subBlocks {
            if let auth = parseAuthor(sub) {
                authors.append(auth)
            } else if let fn = parseFootnote(sub) {
                footnotes.append(fn)
            }
        }

        return TitleBlock(title: title, authors: authors, footnotes: footnotes)
    }

    /// 把 body 里的 @author{...} 和 @footnote{...} 子块切分出来（其余丢弃）
    private static func splitAuthorFootnote(_ body: String) -> [String] {
        var result: [String] = []
        var remaining = Substring(body)

        while !remaining.isEmpty {
            // 找 @author 或 @footnote
            let authorRange = remaining.range(of: "@author")
            let footnoteRange = remaining.range(of: "@footnote")
            let next: Substring.Index? = {
                switch (authorRange, footnoteRange) {
                case let (a?, f?): return a.lowerBound < f.lowerBound ? a.lowerBound : f.lowerBound
                case let (a?, nil): return a.lowerBound
                case let (nil, f?): return f.lowerBound
                default: return nil
                }
            }()

            guard let start = next else { break }

            // 找匹配的 }（大括号可能嵌套，但 author/footnote 内部不嵌套，简单计数）
            if let closeBrace = findMatchingBrace(in: remaining, from: start) {
                let block = String(remaining[start...closeBrace])
                result.append(block)
                remaining = remaining[remaining.index(after: closeBrace)...]
            } else {
                break
            }
        }
        return result
    }

    private static func parseAuthor(_ text: String) -> Author? {
        // 期望 @author{...} 形式（前面可能有空白）
        let trimmed = text.drop(while: { $0.isWhitespace || $0.isNewline })
        guard trimmed.hasPrefix("@author") else { return nil }
        let body = trimmed.dropFirst("@author".count)
        let trimmedBody = body.drop(while: { $0.isWhitespace })
        guard trimmedBody.first == "{" else { return nil }
        // 用 findMatchingBrace 找真正闭合的 }（容错）
        guard let closeBrace = findMatchingBrace(in: trimmedBody, from: trimmedBody.startIndex) else { return nil }
        let inner = String(trimmedBody[trimmedBody.index(after: trimmedBody.startIndex)..<closeBrace])
        let kv = parseKeyValues(inner)
        return Author(
            name: kv["name"] ?? "",
            affiliation: kv["affiliation"],
            email: kv["email"],
            orcid: kv["orcid"],
            note: kv["note"],
            corresponding: kv["corresponding"] == "true"
        )
    }

    private static func parseFootnote(_ text: String) -> Footnote? {
        let trimmed = text.drop(while: { $0.isWhitespace || $0.isNewline })
        guard trimmed.hasPrefix("@footnote") else { return nil }
        let body = trimmed.dropFirst("@footnote".count)
        let trimmedBody = body.drop(while: { $0.isWhitespace })
        guard trimmedBody.first == "{" else { return nil }
        // 用 findMatchingBrace 找真正闭合的 }（容错：避免 dropFirst/dropLast 误删中间的 }）
        guard let closeBrace = findMatchingBrace(in: trimmedBody, from: trimmedBody.startIndex) else { return nil }
        let inner = String(trimmedBody[trimmedBody.index(after: trimmedBody.startIndex)..<closeBrace])
        let (marker, label, rawText) = parseFootnoteFields(inner)
        return Footnote(marker: marker, label: label, text: rawText)
    }

    /// 手写 @footnote 内部字段解析：先找 @marker / @label，剩下文本
    private static func parseFootnoteFields(_ body: String) -> (marker: String, label: String?, text: String) {
        var marker = ""
        var label: String? = nil
        var remaining = Substring(body)

        // 扫描 @marker = "..." 和 @label = "..."
        while !remaining.isEmpty {
            remaining = Substring(remaining.drop(while: { $0.isWhitespace || $0.isNewline }))
            if remaining.isEmpty { break }

            // 找 @ 开头
            guard remaining.first == "@" else { break }
            remaining = remaining.dropFirst()  // 跳 @

            // 读 key
            var kEnd = remaining.startIndex
            while kEnd < remaining.endIndex, remaining[kEnd].isLetter || remaining[kEnd].isNumber || remaining[kEnd] == "_" {
                kEnd = remaining.index(after: kEnd)
            }
            let key = String(remaining[remaining.startIndex..<kEnd])
            remaining = Substring(remaining[kEnd...])

            // 跳过空白和 =
            remaining = Substring(remaining.drop(while: { $0.isWhitespace || $0.isNewline || $0 == "=" }))
            remaining = Substring(remaining.drop(while: { $0.isWhitespace || $0.isNewline }))

            // 读字符串字面量（宽容配对任何引号）
            if remaining.first == "\"" || remaining.first == "\u{201C}" || remaining.first == "\u{201D}" {
                let valueStart = remaining.index(after: remaining.startIndex)
                let closeChars: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
                if let closeQuote = remaining[valueStart...].firstIndex(where: { closeChars.contains($0) }) {
                    let value = String(remaining[valueStart..<closeQuote])
                    if key == "marker" { marker = value }
                    else if key == "label" { label = value }
                    remaining = Substring(remaining[remaining.index(after: closeQuote)...])
                } else {
                    break
                }
            } else {
                break
            }
        }

        // 剩下的全部当裸文本
        let rawText = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        return (marker, label, rawText)
    }

    private static func parseAbstract(_ body: String) -> AbstractBlock? {
        let kv = parseKeyValues(body)
        let keywords = parseStringArray(kv["keywords"] ?? "[]")
        // abstract 内部除 keywords 外的全部文字作为段落
        // 剥离时同时支持 `keywords = [...]` 与 `@keywords = [...]` 两种写法
        // （demo.pml 里字段前缀带 @，但 parseKeyValues 已剥掉 @，所以匹配时不带 @）
        var plainText = body
        if kv["keywords"] != nil {
            // 找包含这一行 keywords 的整行（含可选 @ 前缀），删掉
            let pattern1 = "@keywords\\s*=\\s*\\[[^\\]]*\\]"
            let pattern2 = "keywords\\s*=\\s*\\[[^\\]]*\\]"
            if let regex = try? NSRegularExpression(pattern: pattern1, options: []) {
                let range = NSRange(location: 0, length: (plainText as NSString).length)
                plainText = regex.stringByReplacingMatches(
                    in: plainText, options: [], range: range, withTemplate: ""
                )
            }
            if let regex = try? NSRegularExpression(pattern: pattern2, options: []) {
                let range = NSRange(location: 0, length: (plainText as NSString).length)
                plainText = regex.stringByReplacingMatches(
                    in: plainText, options: [], range: range, withTemplate: ""
                )
            }
        }
        plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = plainText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return AbstractBlock(keywords: keywords, paragraphs: paragraphs)
    }

    private static func parseSection(title: String, level: Section.Level, body: String) -> Section {
        var blocks: [Block] = []
        let remaining = Substring(body)

        // 把 body 切成块：空行分段，每段要么是 @figure/@table/@equation 块，要么是段落
        let paragraphs = splitByBlankLines(remaining)

        for para in paragraphs {
            let p = String(para).trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { continue }

            // Sprint 9.x：section body 内的 "@subsection Title" 行交给顶层 splitTopLevel
            // 处理为独立 subsection block；这里不能再当 paragraph，否则会渲染成垃圾段落
            // 且导致 Sprint 9 paragraph 锚点偏移。
            if p.hasPrefix("@subsection") { continue }

            if p.hasPrefix("@figure") {
                if let fig = parseFigure(p) { blocks.append(.figure(fig)) }
            } else if p.hasPrefix("@table") {
                if let tbl = parseTable(p) { blocks.append(.table(tbl)) }
            } else if p.hasPrefix("@equation") {
                if let eq = parseEquation(p) { blocks.append(.equation(eq)) }
            } else {
                // 段落：解析行内 @cite / @ref
                blocks.append(.paragraph(parseInline(p)))
            }
        }

        return Section(level: level, title: title, blocks: blocks, children: [])
    }

    private static func parseFigure(_ text: String) -> Figure? {
        let inner = extractBracedBody(text, keyword: "@figure")
        guard let inner = inner else { return nil }
        let kv = parseKeyValues(inner)
        return Figure(
            path: kv["path"] ?? "",
            caption: kv["caption"] ?? "",
            label: kv["label"]
        )
    }

    private static func parseTable(_ text: String) -> Table? {
        let inner = extractBracedBody(text, keyword: "@table")
        guard let inner = inner else { return nil }
        let kv = parseKeyValues(inner)
        return Table(
            caption: kv["caption"] ?? "",
            label: kv["label"],
            columns: parseStringArray(kv["columns"] ?? "[]"),
            rows: parseStringArray2D(kv["rows"] ?? "[]")
        )
    }

    private static func parseEquation(_ text: String) -> Equation? {
        let inner = extractBracedBody(text, keyword: "@equation")
        guard let inner = inner else { return nil }
        let kv = parseKeyValues(inner)
        return Equation(content: kv["content"] ?? "", label: kv["label"])
    }

    // MARK: - 行内解析

    /// 解析段落里的 @cite{...} / @ref{...} / $...$ / $$...$$
    private static func parseInline(_ text: String) -> [Inline] {
        var inlines: [Inline] = []
        var remaining = Substring(text)

        while !remaining.isEmpty {
            // 优先匹配 $$...$$ 块级数学（用单独 case，下一个 if 检测避免和 $...$ 冲突）
            if let blockMath = findInlineMath(in: remaining, block: true) {
                if blockMath.start > remaining.startIndex {
                    inlines.append(contentsOf: tokenizeTextOrSimple(String(remaining[remaining.startIndex..<blockMath.start])))
                }
                inlines.append(.math(blockMath.content))
                remaining = remaining[blockMath.end...]
            } else if let inlineMath = findInlineMath(in: remaining, block: false) {
                if inlineMath.start > remaining.startIndex {
                    inlines.append(contentsOf: tokenizeTextOrSimple(String(remaining[remaining.startIndex..<inlineMath.start])))
                }
                inlines.append(.math(inlineMath.content))
                remaining = remaining[inlineMath.end...]
            } else if let citeRange = remaining.range(of: "@cite{") {
                if citeRange.lowerBound > remaining.startIndex {
                    inlines.append(.text(String(remaining[remaining.startIndex..<citeRange.lowerBound])))
                }
                if let close = findMatchingBrace(in: remaining, from: citeRange.upperBound) {
                    let key = String(remaining[citeRange.upperBound..<close])
                    inlines.append(.citation(key: key))
                    remaining = remaining[remaining.index(after: close)...]
                } else {
                    inlines.append(.text(String(remaining)))
                    return inlines
                }
            } else if let refRange = remaining.range(of: "@ref{") {
                if refRange.lowerBound > remaining.startIndex {
                    inlines.append(.text(String(remaining[remaining.startIndex..<refRange.lowerBound])))
                }
                if let close = findMatchingBrace(in: remaining, from: refRange.upperBound) {
                    let label = String(remaining[refRange.upperBound..<close])
                    inlines.append(.reference(label: label))
                    remaining = remaining[remaining.index(after: close)...]
                } else {
                    inlines.append(.text(String(remaining)))
                    return inlines
                }
            } else {
                inlines.append(.text(String(remaining)))
                break
            }
        }
        return inlines
    }

    // MARK: - 通用小工具

    private static func findMatchingBrace(in source: Substring, from start: Substring.Index) -> Substring.Index? {
        var depth = 0
        var i = start
        while i < source.endIndex {
            if source[i] == "{" { depth += 1 }
            else if source[i] == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// 提取 `@keyword{...}` 的大括号内部内容
    private static func extractBracedBody(_ text: String, keyword: String) -> String? {
        guard text.hasPrefix(keyword) else { return nil }
        let after = text.dropFirst(keyword.count)
        let trimmed = after.drop(while: { $0.isWhitespace })
        guard trimmed.first == "{" else { return nil }
        // 简单截取首尾 { }（假设不嵌套，demo.pml 满足）
        let inner = trimmed.dropFirst().dropLast()
        return String(inner)
    }

    /// 解析 `key = "value"` 形式的 KV 对
    private static func parseKeyValues(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        var remaining = Substring(body)

        while !remaining.isEmpty {
            // 跳过空白
            remaining = Substring(remaining.drop(while: { $0.isWhitespace || $0.isNewline }))
            if remaining.isEmpty { break }

            // 读 key（可选 @ 前缀）
            var kStart = remaining.startIndex
            if kStart < remaining.endIndex, remaining[kStart] == "@" {
                kStart = remaining.index(after: kStart)
            }
            var kEnd = kStart
            while kEnd < remaining.endIndex, remaining[kEnd].isLetter || remaining[kEnd].isNumber || remaining[kEnd] == "_" {
                kEnd = remaining.index(after: kEnd)
            }
            let key = String(remaining[kStart..<kEnd])
            remaining = Substring(remaining[kEnd...])

            // 看 key 后面是否有 = （即是否是真正的 key=value）
            // 跳过空白检查下一个非空白字符
            let afterKeyWhitespace = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
            if afterKeyWhitespace.first != "=" {
                // 不是 key=value 形式——直接 break，不向 result 注入任何残留文本
                // 容错策略：宁可丢字段，也不要让源码透传到 AST
                break
            }

            // 跳过空白和 =
            remaining = Substring(remaining.drop(while: { $0.isWhitespace || $0 == "=" }))

            // 读 value（"..." 或 [...]）
            if let openQuote = remaining.first, openQuote == "\"" || openQuote == "\u{201C}" || openQuote == "\u{201D}" {
                // 字符串字面量：宽容配对——任何引号（ASCII / 中文左右弯）都能闭合
                let valueStart = remaining.index(after: remaining.startIndex)
                let closeChars: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
                if let closeQuote = remaining[valueStart...].firstIndex(where: { closeChars.contains($0) }) {
                    let value = String(remaining[valueStart..<closeQuote])
                    result[key] = value
                    remaining = Substring(remaining[remaining.index(after: closeQuote)...])
                } else {
                    break
                }
            } else if remaining.first == "[" {
                // 数组
                var depth = 0
                var i = remaining.startIndex
                while i < remaining.endIndex {
                    if remaining[i] == "[" { depth += 1 }
                    else if remaining[i] == "]" {
                        depth -= 1
                        if depth == 0 {
                            let value = String(remaining[remaining.startIndex...i])
                            result[key] = value
                            remaining = Substring(remaining[remaining.index(after: i)...])
                            break
                        }
                    }
                    i = remaining.index(after: i)
                }
                if depth != 0 { break }
            } else {
                // 裸值（true/false/number），读到空白/换行
                var vEnd = remaining.startIndex
                while vEnd < remaining.endIndex, !remaining[vEnd].isWhitespace && remaining[vEnd] != "\n" {
                    vEnd = remaining.index(after: vEnd)
                }
                let value = String(remaining[remaining.startIndex..<vEnd])
                result[key] = value
                remaining = Substring(remaining[vEnd...])
            }
        }

        // 容错策略：不再向 result 注入 __text__ 累积，避免源码透传到 AST
        // 注释：之前在循环末尾累积 leftover 到 __text__，会导致未消化的源码被 parseFootnote 当 text
        return result
    }

    /// `["a", "b"]` → `["a", "b"]`
    private static func parseStringArray(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return [] }
        let inner = String(trimmed.dropFirst().dropLast())
        var result: [String] = []
        var current = ""
        var inString = false
        for ch in inner {
            if ch == "\"" {
                inString.toggle()
                if !inString {
                    result.append(current)
                    current = ""
                }
            } else if inString {
                current.append(ch)
            }
        }
        return result
    }

    /// `[["a","b"], ["c","d"]]` → `[["a","b"], ["c","d"]]`
    private static func parseStringArray2D(_ raw: String) -> [[String]] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return [] }
        let inner = String(trimmed.dropFirst().dropLast())
        var rows: [[String]] = []
        var current: [String] = []
        var str = ""
        var inString = false
        var depth = 0

        for ch in inner {
            if ch == "\"" {
                inString.toggle()
                if !inString { current.append(str); str = "" }
            } else if inString {
                str.append(ch)
            } else if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0 && !current.isEmpty {
                    rows.append(current)
                    current = []
                }
            }
        }
        return rows
    }

    /// 按空行（连续两个换行）切分
    private static func splitByBlankLines(_ source: Substring) -> [Substring] {
        var result: [Substring] = []
        var currentStart = source.startIndex
        var i = source.startIndex
        var lastWasNewline = false

        while i < source.endIndex {
            let ch = source[i]
            if ch.isNewline {
                if lastWasNewline {
                    // 空行：切分
                    if currentStart < i {
                        result.append(source[currentStart..<source.index(before: i)])
                    }
                    currentStart = source.index(after: i)
                }
                lastWasNewline = true
            } else {
                lastWasNewline = false
            }
            i = source.index(after: i)
        }
        if currentStart < source.endIndex {
            result.append(source[currentStart...])
        }
        return result
    }

    // MARK: - $...$ / $$...$$ 数学公式

    /// 找到第一对 $$...$$ 或 $...$ 的位置和内容
    private struct MathMatch {
        let start: Substring.Index
        let end: Substring.Index     // 闭合 $ 之后的位置
        let content: String
    }

    private static func findInlineMath(in source: Substring, block: Bool) -> MathMatch? {
        let openDelim = block ? "$$" : "$"
        guard let openRange = source.range(of: openDelim) else { return nil }

        // 从开分隔符后开始找闭分隔符
        let afterOpen = openRange.upperBound
        guard let closeRange = source.range(of: openDelim, range: afterOpen..<source.endIndex) else {
            return nil
        }

        let content = String(source[afterOpen..<closeRange.lowerBound])
        return MathMatch(start: openRange.lowerBound, end: closeRange.upperBound, content: content)
    }

    /// 把普通文本切成 Inline 列表（暂只返回单一 .text，未来可扩展识别更多行内语法）
    private static func tokenizeTextOrSimple(_ text: String) -> [Inline] {
        if text.isEmpty { return [] }
        return [.text(text)]
    }

    /// 去掉 // 注释（从 // 到行尾）
    private static func stripComments(_ source: String) -> String {
        var result = ""
        var i = source.startIndex
        while i < source.endIndex {
            if source[i] == "/", source.index(after: i) < source.endIndex,
               source[source.index(after: i)] == "/" {
                // 跳过到行尾
                while i < source.endIndex, !source[i].isNewline {
                    i = source.index(after: i)
                }
            } else {
                result.append(source[i])
                i = source.index(after: i)
            }
        }
        return result
    }
}

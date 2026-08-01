//
//  HTMLRenderer.swift
//  PaperLink
//
//  PaperMLDocument AST → HTML string。
//  Visitor 模式，方便未来加 PDF / LaTeX / Docx 输出。
//
//  样式：极简（无 KaTeX / 无外部 CSS），先让 demo 跑出"像论文"的样子。
//  公式：原样显示 LaTeX 源码（不渲染）
//  图片：用灰色占位框 + 路径名
//

import Foundation

enum HTMLRenderer {

    /// 渲染 PaperML 文档为完整 HTML 字符串（带 inline CSS + KaTeX CDN）
    ///
    /// - Parameter rootURL: 当前 .pml 文件的所在目录。`@path` 里的 `figures/xxx.png` 优先从这里解析；
    ///                     找不到再 fallback 到 Bundle.main（开发期 demo 图）。传 nil 时只查 Bundle。
    static func render(_ doc: PaperMLDocument, rootURL: URL? = nil) -> String {
        var html = ""
        html += "<!DOCTYPE html>\n<html><head><meta charset='utf-8'>"
        html += "<style>\(css)\n</style>"

        // KaTeX CDN（CSS + JS + auto-render）
        html += """
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" crossorigin="anonymous">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js" crossorigin="anonymous"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js" crossorigin="anonymous"
            onload="renderMathInElement(document.body, {
                delimiters: [
                    {left: '$$', right: '$$', display: true},
                    {left: '$', right: '$', display: false},
                    {left: '\\\\[', right: '\\\\]', display: true},
                    {left: '\\\\(', right: '\\\\)', display: false}
                ],
                throwOnError: false
            });"></script>
        """

        html += "</head><body>"

        if let title = doc.metadata.title {
            html += renderTitle(title)
        }
        if let abs = doc.metadata.abstract {
            html += renderAbstract(abs)
        }
        for section in doc.sections {
            html += renderSection(section, rootURL: rootURL)
        }
        html += "</body></html>"
        return html
    }

    // MARK: - 公共：图路径 → 相对路径（HTML 里的 <img src>）
    //
    // 返回字符串永远是 **相对路径**（无 file:// 前缀），由 HTMLPreview 的 baseURL 决定根：
    //   - 用户 .pml（fileURL != nil）→ baseURL = fileURL 所在目录 → 同目录 figures/ 自动解析
    //   - bundle 内 demo.pml（fileURL == nil）→ baseURL = Bundle.main.resourceURL → bundle 内 figures/ 自动解析
    //
    // 存在性检查（用于在 HTML 中显示占位符 vs 真图）：
    //   1. `<rootURL>/<relativePath>`（按原始相对路径拼，保留 figures/ 前缀）
    //   2. `Bundle.main/<relativePath>`（demo 图 fallback；Bundle API 自动处理 subdirectory）
    //
    // 返回 nil 表示找不到，对应 HTML 显示 `[image not found]`。

    static func figureRelativePath(_ relativePath: String, rootURL: URL?) -> String? {
        // 1. 用户文档：按原始相对路径拼到 rootURL 所在目录
        if let rootURL = rootURL {
            let dir = rootURL.hasDirectoryPath ? rootURL : rootURL.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return relativePath
            }
        }

        // 2. Bundle fallback（demo 图）。这里我们 *不* 验证文件存在，因为 bundle API
        // 不拆 subdirectory；只要 @path 是 figures/<x> 形式，HTMLPreview 的 baseURL
        // 是 Bundle.main.resourceURL，就一定能解析。
        if relativePath.hasPrefix("figures/") {
            let cleaned = String(relativePath.dropFirst("figures/".count))
            if Bundle.main.url(forResource: cleaned, withExtension: nil, subdirectory: "figures") != nil {
                return relativePath
            }
        }
        if Bundle.main.url(forResource: relativePath, withExtension: nil) != nil {
            return relativePath
        }

        return nil
    }

    // MARK: - Title / Abstract

    private static func renderTitle(_ title: TitleBlock) -> String {
        // footnote label → marker 映射（例如 "equal_contribution" → "†"）
        let labelToMarker: [String: String] = Dictionary(
            uniqueKeysWithValues: title.footnotes.compactMap { fn in
                guard let label = fn.label else { return nil }
                return (label, fn.marker)
            }
        )

        var s = "<div class='title-block'>"
        s += "<h1 class='paper-title'>\(escape(title.title))</h1>"
        s += "<div class='authors'>"
        for (idx, author) in title.authors.enumerated() {
            s += "<span class='author'>"
            s += "<b>\(escape(author.name))</b>"
            // 根据 note 字段输出对应脚注 marker
            if let note = author.note, let marker = labelToMarker[note] {
                s += "<sup class='fn-mark'>\(escape(marker))</sup>"
            }
            if author.corresponding {
                s += "<sup class='fn-mark'>*</sup>"
            }
            if let aff = author.affiliation { s += "<span class='aff'> · \(escape(aff))</span>" }
            if let email = author.email { s += "<span class='email'> · \(escape(email))</span>" }
            s += "</span>"
            if idx < title.authors.count - 1 { s += "<span class='sep'> · </span>" }
        }
        s += "</div>"
        if !title.footnotes.isEmpty {
            s += "<div class='footnotes'>"
            for fn in title.footnotes {
                s += "<p class='footnote'><sup>\(escape(fn.marker))</sup> \(escape(fn.text))</p>"
            }
            s += "</div>"
        }
        s += "</div>"
        return s
    }

    private static func renderAbstract(_ abs: AbstractBlock) -> String {
        var s = "<div class='abstract'>"
        s += "<h2>Abstract</h2>"
        for p in abs.paragraphs {
            s += "<p>\(escape(p))</p>"
        }
        if !abs.keywords.isEmpty {
            s += "<p class='keywords'><b>Keywords:</b> \(abs.keywords.map { escape($0) }.joined(separator: ", "))</p>"
        }
        s += "</div>"
        return s
    }

    // MARK: - Section

    private static func renderSection(_ section: Section, rootURL: URL?) -> String {
        let levelClass = section.level == .section ? "section-h1" : "section-h2"
        let tag = section.level == .section ? "h2" : "h3"
        var s = "<\(tag) class='\(levelClass)'>\(escape(section.title))</\(tag)>"
        for block in section.blocks {
            s += renderBlock(block, rootURL: rootURL)
        }
        // 递归渲染嵌套的 subsection
        for child in section.children {
            s += "<div class='subsection-group'>"
            s += renderSection(child, rootURL: rootURL)
            s += "</div>"
        }
        return s
    }

    // MARK: - Block

    private static func renderBlock(_ block: Block, rootURL: URL?) -> String {
        switch block {
        case .paragraph(let inlines):
            return "<p>\(renderInlines(inlines))</p>"
        case .figure(let fig):
            var s = "<figure>"
            if let rel = figureRelativePath(fig.path, rootURL: rootURL) {
                s += "<img src='\(escape(rel))' alt='\(escape(fig.caption))' class='figure-img' />"
            } else {
                s += "<div class='figure-placeholder'>[image not found: \(escape(fig.path))]</div>"
            }
            s += "<figcaption><b>Figure</b>. \(escape(fig.caption))"
            if let label = fig.label { s += " <span class='label'>\(escape(label))</span>" }
            s += "</figcaption></figure>"
            return s
        case .table(let tbl):
            var s = "<figure class='table-figure'>"
            s += "<table>"
            s += "<thead><tr>"
            for col in tbl.columns {
                s += "<th>\(escape(col))</th>"
            }
            s += "</tr></thead><tbody>"
            for row in tbl.rows {
                s += "<tr>"
                for cell in row {
                    s += "<td>\(escape(cell))</td>"
                }
                s += "</tr>"
            }
            s += "</tbody></table>"
            s += "<figcaption><b>Table</b>. \(escape(tbl.caption))"
            if let label = tbl.label { s += " <span class='label'>\(escape(label))</span>" }
            s += "</figcaption></figure>"
            return s
        case .equation(let eq):
            // content 已经是 LaTeX 源码，包成 $$...$$ 让 KaTeX 块级渲染
            return "<div class='equation'>" +
                   "$\(escape(eq.content))$" +
                   (eq.label.map { "<span class='eq-label'>\(escape($0))</span>" } ?? "") +
                   "</div>"
        }
    }

    // MARK: - Inline

    private static func renderInlines(_ inlines: [Inline]) -> String {
        var s = ""
        var citeCounter = 0
        var refMap: [String: Int] = [:]   // label → 上标编号
        var refCounter = 0

        for inline in inlines {
            switch inline {
            case .text(let t):
                s += escape(t)
            case .citation(let key):
                citeCounter += 1
                // [n] 角标 + 显示 key（如 (vaswani2017)）
                s += "<sup class='cite'>[\(citeCounter)]</sup><span class='cite-key'>\(escape(key))</span>"
                _ = key
            case .reference(let label):
                if let n = refMap[label] {
                    s += "<sup class='ref'>\(n)</sup>"
                } else {
                    refCounter += 1
                    refMap[label] = refCounter
                    s += "<sup class='ref'>\(refCounter)</sup>"
                }
            case .math(let m):
                // 包成 $...$ 让 KaTeX auto-render 抓到（行内数学）
                s += "$\(escape(m))$"
            }
        }
        return s
    }

    // MARK: - 工具

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let css = """
    :root {
        color-scheme: light dark;
        --fg: #1d1d1f;
        --fg-secondary: #6e6e73;
        --fg-tertiary: #98989d;
        --bg: #ffffff;
        --bg-subtle: #fafafb;
        --border: #e5e5e7;
        --accent: #0066cc;
        --danger: #c00;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --fg: #f5f5f7;
            --fg-secondary: #a1a1a6;
            --fg-tertiary: #6e6e73;
            --bg: #1c1c1e;
            --bg-subtle: #2c2c2e;
            --border: #38383a;
            --accent: #2997ff;
            --danger: #ff6961;
        }
    }
    * { box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "PingFang SC", sans-serif;
        max-width: 100%;
        margin: 0 auto;
        padding: 40px 28px 64px;
        line-height: 1.65;
        color: var(--fg);
        background: var(--bg);
        font-size: 15px;
        overflow-x: hidden;
        -webkit-font-smoothing: antialiased;
    }
    .title-block {
        text-align: center;
        margin-bottom: 40px;
        padding-bottom: 28px;
        border-bottom: 1px solid var(--border);
    }
    .paper-title {
        font-size: 26px;
        font-weight: 700;
        margin: 0 0 18px;
        letter-spacing: -0.01em;
        line-height: 1.3;
    }
    .authors {
        font-size: 14px;
        color: var(--fg-secondary);
        line-height: 1.8;
    }
    .author { white-space: nowrap; }
    .author b { color: var(--fg); font-weight: 600; }
    .aff, .email { color: var(--fg-tertiary); font-size: 12px; }
    .fn-mark { color: var(--danger); margin-left: 1px; font-size: 11px; }
    .footnotes {
        margin-top: 14px;
        font-size: 12px;
        color: var(--fg-secondary);
        text-align: left;
        line-height: 1.5;
    }
    .footnote { margin: 2px 0; }
    .abstract {
        background: var(--bg-subtle);
        border-radius: 8px;
        padding: 20px 24px;
        margin: 0 0 40px;
        font-size: 14px;
    }
    .abstract h2 {
        font-size: 11px;
        font-weight: 600;
        margin: 0 0 10px;
        text-transform: uppercase;
        letter-spacing: 1.2px;
        color: var(--fg-tertiary);
    }
    .abstract p { margin: 0 0 8px; text-align: justify; }
    .keywords {
        font-size: 12px;
        color: var(--fg-secondary);
        margin-top: 12px;
        padding-top: 10px;
        border-top: 1px solid var(--border);
    }
    .keywords b { color: var(--fg); font-weight: 600; }
    h2.section-h1 {
        font-size: 22px;
        font-weight: 700;
        margin: 40px 0 16px;
        letter-spacing: -0.01em;
    }
    h3.section-h2 {
        font-size: 17px;
        font-weight: 600;
        margin: 28px 0 12px;
        color: var(--fg);
    }
    .subsection-group { margin-left: 0; }
    p { text-align: justify; margin: 10px 0; }
    .cite {
        color: var(--accent);
        font-size: 11px;
        padding: 0 1px;
        font-weight: 500;
    }
    .cite-key, .ref-key {
        color: var(--fg-tertiary);
        font-size: 10px;
        margin: 0 3px;
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
    }
    .ref {
        color: var(--accent);
        font-size: 11px;
        font-weight: 500;
    }
    figure { margin: 28px 0; }
    .figure-img {
        max-width: 100%;
        height: auto;
        display: block;
        margin: 0 auto;
        border-radius: 6px;
    }
    .figure-placeholder {
        background: var(--bg-subtle);
        border: 1px dashed var(--border);
        border-radius: 6px;
        padding: 48px 16px;
        text-align: center;
        color: var(--fg-tertiary);
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
        font-size: 12px;
    }
    .table-figure { margin: 28px 0; }
    table {
        border-collapse: collapse;
        width: 100%;
        font-size: 13px;
        border: 1px solid var(--border);
        border-radius: 6px;
        overflow: hidden;
    }
    th, td {
        border-bottom: 1px solid var(--border);
        padding: 10px 14px;
        text-align: left;
    }
    tr:last-child td { border-bottom: none; }
    th {
        background: var(--bg-subtle);
        font-weight: 600;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.4px;
        color: var(--fg-secondary);
    }
    figcaption {
        font-size: 12px;
        color: var(--fg-secondary);
        margin-top: 8px;
        text-align: left;
        line-height: 1.5;
    }
    .label {
        color: var(--fg-tertiary);
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
        font-size: 11px;
        margin-left: 6px;
    }
    .equation {
        text-align: center;
        margin: 24px 0;
        padding: 14px;
        background: var(--bg-subtle);
        border-radius: 6px;
    }
    .eq-content {
        font-family: "STIX", "Latin Modern Math", serif;
        font-style: italic;
    }
    .eq-label {
        display: block;
        font-size: 11px;
        color: var(--fg-tertiary);
        margin-top: 6px;
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
    }
    """
}

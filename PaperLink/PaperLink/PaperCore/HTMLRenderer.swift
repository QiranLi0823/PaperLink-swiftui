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
    static func render(_ doc: PaperMLDocument) -> String {
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
            html += renderSection(section)
        }
        html += "</body></html>"
        return html
    }

    // MARK: - 公共：图路径转 file:// URL
    // 找 Bundle 里 figures/<path>，没有就 fallback 到占位符

    private static func figureURL(_ relativePath: String) -> String? {
        // 去掉前导 "figures/" 再拼绝对路径
        let cleaned = relativePath.hasPrefix("figures/") ? String(relativePath.dropFirst("figures/".count)) : relativePath
        if let bundleURL = Bundle.main.url(forResource: "figures/\(cleaned)", withExtension: nil) {
            return bundleURL.absoluteString
        }
        if let bundleURL = Bundle.main.url(forResource: cleaned, withExtension: nil) {
            return bundleURL.absoluteString
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

    private static func renderSection(_ section: Section) -> String {
        let levelClass = section.level == .section ? "section-h1" : "section-h2"
        let tag = section.level == .section ? "h2" : "h3"
        var s = "<\(tag) class='\(levelClass)'>\(escape(section.title))</\(tag)>"
        for block in section.blocks {
            s += renderBlock(block)
        }
        // 递归渲染嵌套的 subsection
        for child in section.children {
            s += "<div class='subsection-group'>"
            s += renderSection(child)
            s += "</div>"
        }
        return s
    }

    // MARK: - Block

    private static func renderBlock(_ block: Block) -> String {
        switch block {
        case .paragraph(let inlines):
            return "<p>\(renderInlines(inlines))</p>"
        case .figure(let fig):
            var s = "<figure>"
            if let url = figureURL(fig.path) {
                s += "<img src='\(url)' alt='\(escape(fig.caption))' class='figure-img' />"
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
    body {
        font-family: -apple-system, "Helvetica Neue", "PingFang SC", sans-serif;
        max-width: 820px;
        margin: 32px auto;
        padding: 0 24px;
        line-height: 1.6;
        color: #1a1a1a;
        background: #fff;
    }
    .title-block { text-align: center; margin-bottom: 24px; }
    .paper-title { font-size: 22px; font-weight: 700; margin: 0 0 12px; }
    .authors { font-size: 14px; color: #444; }
    .author { white-space: nowrap; }
    .aff, .email { color: #666; font-size: 12px; }
    .corr { color: #c00; font-weight: 700; }
    .fn-mark { color: #c00; margin-left: 1px; }
    .footnotes { margin-top: 8px; font-size: 12px; color: #666; text-align: left; }
    .footnote { margin: 2px 0; }
    .abstract { background: #f7f7f9; border-left: 3px solid #3a7; padding: 12px 16px; margin: 16px 0; font-size: 14px; }
    .abstract h2 { font-size: 14px; margin: 0 0 8px; text-transform: uppercase; color: #555; }
    .keywords { font-size: 12px; color: #555; }
    h2.section-h1 { font-size: 20px; border-bottom: 1px solid #ddd; padding-bottom: 4px; margin-top: 32px; }
    h3.section-h2 { font-size: 16px; margin-top: 20px; color: #222; }
    .subsection-group { margin-left: 16px; }
    p { text-align: justify; margin: 8px 0; }
    .cite, .ref { color: #c33; font-size: 11px; padding: 0 1px; }
    .cite-key, .ref-key { color: #888; font-size: 10px; margin: 0 2px; font-family: monospace; }
    .math { background: #f0f4f8; padding: 1px 4px; border-radius: 3px; font-family: "SF Mono", Menlo, monospace; font-size: 12px; }
    figure { margin: 16px 0; }
    .figure-img { max-width: 100%; height: auto; display: block; margin: 0 auto; border: 1px solid #ddd; }
    .figure-placeholder { background: #eef; border: 1px dashed #99c; padding: 40px 16px; text-align: center; color: #669; font-family: monospace; }
    .table-figure { margin: 16px 0; }
    table { border-collapse: collapse; width: 100%; font-size: 13px; }
    th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
    th { background: #f5f5f5; font-weight: 600; }
    figcaption { font-size: 12px; color: #555; margin-top: 6px; text-align: left; }
    .label { color: #888; font-family: monospace; }
    .equation { text-align: center; margin: 16px 0; padding: 8px; background: #fafafa; border-radius: 4px; }
    .eq-content { font-family: "STIX", "Latin Modern Math", serif; font-style: italic; }
    .eq-label { display: block; font-size: 11px; color: #888; margin-top: 4px; }
    """
}

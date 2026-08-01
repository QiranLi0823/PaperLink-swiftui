//
//  PaperMLAST.swift
//  PaperLink
//
//  PaperML 抽象语法树。纯 Swift 枚举 + 结构体，零外部依赖。
//  设计目标：
//  1. 完整表达 demo.pml 出现的所有结构
//  2. 方便未来转 doc / latex（结构清晰 + Visitor 模式友好）
//  3. 节点属性都直接展开（避免嵌套过深）
//

import Foundation

// MARK: - 文档根

/// PaperML 文档根节点
struct PaperMLDocument: Equatable {
    var metadata: Metadata
    var sections: [Section]

    /// 顶层元数据（title / abstract）
    struct Metadata: Equatable {
        var title: TitleBlock?
        var abstract: AbstractBlock?
    }
}

// MARK: - 顶层块

/// @title{...}
struct TitleBlock: Equatable {
    var title: String
    var authors: [Author]
    var footnotes: [Footnote]
}

/// @author{...}
struct Author: Equatable {
    var name: String
    var affiliation: String?
    var email: String?
    var orcid: String?
    var note: String?
    var corresponding: Bool
}

/// @footnote{...}
struct Footnote: Equatable {
    var marker: String
    var label: String?
    var text: String
}

/// @abstract{...}
struct AbstractBlock: Equatable {
    var keywords: [String]
    var paragraphs: [String]   // abstract 内部的文本段落
}

// MARK: - 章节

/// @section 或 @subsection
struct Section: Equatable, Identifiable {
    let id = UUID()
    var level: Level
    var title: String
    var blocks: [Block]
    /// 嵌套子章节（@subsection 时填入最近的 @section 的 children）
    var children: [Section]

    enum Level: Equatable {
        case section       // 一级
        case subsection    // 二级
    }
}

// MARK: - 块级内容（章节内部）

/// 章节内部的块
enum Block: Equatable {
    /// 普通段落（含行内元素：cite / ref / math）
    case paragraph([Inline])
    /// @figure{...}
    case figure(Figure)
    /// @table{...}
    case table(Table)
    /// @equation{...}
    case equation(Equation)
}

/// @figure{...}
struct Figure: Equatable {
    var path: String
    var caption: String
    var label: String?
}

/// @table{...}
struct Table: Equatable {
    var caption: String
    var label: String?
    var columns: [String]
    var rows: [[String]]
}

/// @equation{...}
struct Equation: Equatable {
    var content: String    // LaTeX 源码（暂不渲染）
    var label: String?
}

// MARK: - 行内元素

/// 段落内部的行内元素
enum Inline: Equatable {
    /// 普通文本
    case text(String)
    /// @cite{key}
    case citation(key: String)
    /// @ref{label}
    case reference(label: String)
    /// $...$ 行内数学
    case math(String)
}

//
//  ParseError.swift
//  PaperLink
//
//  Phase 1 Sprint 1: 解析错误诊断。
//  Parser 内部收集错误，UI 层展示行号 + 信息。
//

import Foundation

/// 解析错误
struct ParseError: Equatable, Identifiable {
    let id = UUID()
    /// 错误级别
    enum Severity: String, Equatable {
        case error      // 阻止节点构造
        case warning    // 容错但可疑
    }

    let severity: Severity
    /// 源码位置（1-based）
    let line: Int
    let column: Int
    /// 用户可读的错误信息
    let message: String

    /// 用于 UI 显示的简短形式
    var shortDescription: String {
        "第 \(line) 行第 \(column) 列：\(message)"
    }
}

/// 解析结果（含 AST + 错误）
struct ParseResult: Equatable {
    let document: PaperMLDocument?
    let errors: [ParseError]

    var hasErrors: Bool { !errors.isEmpty }
}

// MARK: - 字符串 offset → line/column

extension String {
    /// 把 0-based 字符串 offset 转成 1-based line/column
    func position(at offset: Int) -> (line: Int, column: Int) {
        let safeOffset = max(0, min(offset, count))
        let prefix = self.prefix(safeOffset)
        let line = prefix.filter { $0 == "\n" }.count + 1
        // 计算 column：最后一个换行符之后的字符数 + 1
        let lastNewline = prefix.lastIndex(of: "\n")
        let column: Int
        if let lastNewline = lastNewline {
            column = prefix.distance(from: lastNewline, to: prefix.endIndex)
        } else {
            column = safeOffset + 1
        }
        return (line, column)
    }
}

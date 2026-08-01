//
//  ProjectManager.swift
//  PaperLink
//
//  Phase 1 Sprint 2: 文件 Open / Save。
//  NSOpenPanel / NSSavePanel 集成。
//

import AppKit
import Foundation

/// 文件 I/O 管理器
@MainActor
final class ProjectManager {

    static let shared = ProjectManager()
    private init() {}

    /// 显示 Open 对话框，返回用户选择的 .pml 文件 URL
    /// - Parameter completion: 选好文件后回调（用户取消时 url=nil）
    func openPanel(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "打开 PaperML 文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []    // Phase 1: 不限类型
        panel.allowsOtherFileTypes = true
        panel.message = "选择一个 .pml 文件"

        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// 显示 Save 对话框，返回用户选择的保存路径
    /// - Parameter suggestedName: 默认文件名
    func savePanel(suggestedName: String = "untitled.pml", completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.title = "保存 PaperML 文件"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "保存为 .pml 文件"
        panel.canCreateDirectories = true

        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// 从 URL 读取文件内容
    func load(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectError.encoding
        }
        return text
    }

    /// 写文本到 URL
    func save(_ text: String, to url: URL) throws {
        let data = text.data(using: .utf8) ?? Data()
        try data.write(to: url, options: .atomic)
    }

    enum ProjectError: LocalizedError {
        case encoding

        var errorDescription: String? {
            switch self {
            case .encoding: return "文件编码不是 UTF-8"
            }
        }
    }
}

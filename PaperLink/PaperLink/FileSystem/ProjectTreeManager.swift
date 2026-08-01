//
//  ProjectTreeManager.swift
//  PaperLink
//
//  Phase 1 Sprint 3: 扫描当前 .pml 所在目录，构建文件树。
//  支持 .pml / 常见图片 / pdf / 数据文件。
//

import Foundation
import AppKit
import Combine

/// 文件树节点
struct FileNode: Identifiable, Hashable {
    let id: URL          // 用 URL 作 id
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPML: Bool
    let isImage: Bool
    var children: [FileNode]   // 文件为空数组

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
}

/// 项目文件树管理器
@MainActor
final class ProjectTreeManager: ObservableObject {

    @Published private(set) var root: FileNode?
    @Published private(set) var figures: [URL] = []    // figures/ 下所有图

    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "heic"]
    private let pmlExtension = "pml"

    func reload(from rootURL: URL?) {
        guard let rootURL = rootURL else {
            root = nil
            figures = []
            return
        }
        // 目录 = 文件所在目录（不是文件本身）
        let dir = rootURL.hasDirectoryPath ? rootURL : rootURL.deletingLastPathComponent()
        root = buildNode(from: dir, depth: 0)
        figures = scanFigures(in: dir)
    }

    private func buildNode(from url: URL, depth: Int) -> FileNode? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // 排序：目录优先 + 字母序
        let sorted = contents.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir && !bDir }
            return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
        }

        var children: [FileNode] = []
        for child in sorted {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let ext = child.pathExtension.lowercased()

            // 隐藏 .git 等隐藏目录
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }

            if isDir {
                // 递归（深度限制避免无限）
                if depth < 3, let sub = buildNode(from: child, depth: depth + 1) {
                    children.append(sub)
                }
            } else if ext == pmlExtension || imageExtensions.contains(ext) {
                children.append(FileNode(
                    id: child,
                    url: child,
                    name: name,
                    isDirectory: false,
                    isPML: ext == pmlExtension,
                    isImage: imageExtensions.contains(ext),
                    children: []
                ))
            }
        }

        return FileNode(
            id: url,
            url: url,
            name: url.lastPathComponent,
            isDirectory: true,
            isPML: false,
            isImage: false,
            children: children
        )
    }

    private func scanFigures(in dir: URL) -> [URL] {
        let figuresDir = dir.appendingPathComponent("figures")
        let fm = FileManager.default
        guard fm.fileExists(atPath: figuresDir.path),
              let contents = try? fm.contentsOfDirectory(
                at: figuresDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
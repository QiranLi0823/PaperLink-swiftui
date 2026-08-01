//
//  ContentView.swift
//  PaperLink
//
//  Phase 1 Sprint 2+：双栏布局 + 紧凑 toolbar（文件名 + 点击重命名）+ File 菜单。
//

import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var document: PaperDocument
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 紧凑 toolbar：只显示文件名（点击重命名）
            compactToolbar

            HSplitView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PaperML 源")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    LineNumberedEditor(text: $document.source, errors: document.errors)
                        .border(Color.gray.opacity(0.3))
                }
                .padding(8)
                .frame(minWidth: 320)

                VStack(alignment: .leading, spacing: 4) {
                    Text("论文预览")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    HTMLPreview(html: document.html)
                        .border(Color.gray.opacity(0.3))
                }
                .padding(8)
                .frame(minWidth: 420)
            }

            StatusBar(errors: document.errors)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .navigationTitle(currentFileName)
        .onReceive(NotificationCenter.default.publisher(for: .paperLinkStartRename)) { _ in
            startRename()
        }
    }

    private var currentFileName: String {
        document.fileURL?.lastPathComponent ?? "Untitled.pml"
    }

    @ViewBuilder
    private var compactToolbar: some View {
        HStack(spacing: 8) {
            if isRenaming {
                TextField("", text: $renameText, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .onExitCommand { cancelRename() }
                Button("Save") { commitRename() }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { cancelRename() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(action: startRename) {
                    HStack(spacing: 4) {
                        Text(currentFileName)
                            .font(.system(.body, design: .default))
                            .foregroundStyle(.primary)
                        if document.isDirty {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("点击重命名")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
    }

    private func startRename() {
        renameText = currentFileName
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != currentFileName {
            document.rename(to: trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
        renameText = currentFileName
    }
}

// MARK: - WKWebView 包装

struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }
}

// MARK: - 状态栏

struct StatusBar: View {
    let errors: [ParseError]

    var body: some View {
        HStack(spacing: 8) {
            if let first = errors.first {
                Image(systemName: first.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                    .foregroundStyle(first.severity == .error ? .red : .orange)
                Text("\(errors.count) 个错误")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(first.shortDescription)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("解析正常")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
        .border(Color.gray.opacity(0.2), width: 0.5)
    }
}

#Preview {
    ContentView()
        .environmentObject(PaperDocument())
}

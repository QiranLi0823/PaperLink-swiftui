# Phase 0 — 环境 + 双栏 MVP 计划

> 起点：SwiftUI macOS 应用已创建，空白窗口能启动。
> 目标：在 Phase 0 结束时，能用 SwiftUI 双栏 IDE 编辑 PaperML，实时看到 HTML 预览。
> 范围：macOS only
> 文档版本：v0.1
> 创建日期：2026-08-01
> 后续：完成 Phase 0 后进入 Phase 1（错误诊断 / 高亮 / 补全 / 文件系统 / BibTeX / 导出）

---

## 一、Phase 0 目标

**一句话**：把"空白窗口 + Rust 引擎"打通到"能编辑 PaperML 看 HTML 预览"，验证 SwiftUI + Rust C-ABI 转型在 macOS 上完全可行。

**完成标志**：
- [ ] 启动应用 < 1 秒
- [ ] 双栏布局（HSplitView）正常显示
- [ ] 左侧 NSTextView 编辑 PaperML
- [ ] 右侧 WKWebView 实时渲染 HTML
- [ ] 编辑 → 200ms debounce → 调 Rust → 预览更新
- [ ] KaTeX 公式能正确渲染
- [ ] 应用包 < 50 MB
- [ ] `swift build` 无 warning

---

## 二、本周（Day 1-7）任务清单

### Day 1-2：Rust 引擎改 staticlib + C-ABI 暴露

> 现状：空白窗口已能跑；paper-core 还在 rlib 状态。
> 目标：让 Swift 能调 Rust 函数拿到 HTML 字符串。

#### 2.1 改 paper-core 为 staticlib

**`paper-core/Cargo.toml`** 增加：
```toml
[lib]
crate-type = ["staticlib", "rlib"]
```

**验证**：
```bash
cd paper-core
cargo build --release
# 产出 target/release/libpaper_core.a
```

#### 2.2 暴露最简 C-ABI

**`paper-core/src/lib.rs`**：
```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn paper_parse(input: *const c_char) -> *mut c_char {
    let c_str = unsafe { CStr::from_ptr(input) };
    let input_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    // 调用现有 parse_and_render
    let html = paper_core::parse_and_render(input_str);

    CString::new(html).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn paper_string_free(s: *mut c_char) {
    if s.is_null() { return; }
    unsafe { let _ = CString::from_raw(s); }
}
```

**验证**：
```bash
cargo build --release
nm -g target/release/libpaper_core.a | grep paper_
# 看到 paper_parse / paper_string_free
```

#### 2.3 加 cbindgen（Phase 0 不强求生成头文件，先手写最小头文件）

**`paper-core/paper-core.h`**（手写最小版）：
```c
#ifndef PAPER_CORE_H
#define PAPER_CORE_H

#include <stdint.h>
#include <stddef.h>

char* paper_parse(const char* input);
void  paper_string_free(char* s);

#endif
```

**Phase 0 决策**：先用手写头文件跑通；cbindgen 自动生成推迟到 Phase 1 Sprint 3（因为 Phase 0 还没引入 `PaperDiagnostic`，不需要 cbindgen 的复杂结构生成）。

---

### Day 3-4：SwiftPM 配置 + Swift 端 FFI 封装

#### 3.1 Package.swift 链接 Rust 静态库

**`PaperStudio/Package.swift`**：
```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PaperStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PaperStudio",
            path: "Sources/PaperStudio",
            resources: [
                .copy("../../paper-core/target/release/libpaper_core.a"),
                .copy("Resources/katex"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),  // paper-core 依赖
                .unsafeFlags([
                    "-L", "../../paper-core/target/release",
                    "-l", "paper_core",
                ]),
            ]
        ),
    ]
)
```

> ⚠️ **注意**：SPM 链接静态库路径比较 tricky，如果上面不行就用 **Xcode 工程方案** —— 在 Xcode 里手动加 library 搜索路径，Phase 0 用 Xcode 启动，后续看情况切回纯 SPM。

#### 3.2 Swift FFI 封装

**`Sources/PaperStudio/PaperCore/PaperEngine.swift`**：
```swift
import Foundation

enum PaperEngine {
    private static let paperCore = loadPaperCore()

    /// 加载 Rust 静态库
    private static func loadPaperCore() -> UnsafeMutableRawPointer? {
        // SwiftPM / Bundle 路径处理
        guard let path = Bundle.module.path(forResource: "libpaper_core", ofType: "a") else {
            print("⚠️ libpaper_core.a not found in bundle")
            return nil
        }
        return dlopen(path, RTLD_NOW)
    }

    /// 解析 PaperML → HTML
    static func parse(_ input: String) -> String? {
        guard paperCore != nil else { return nil }

        let result = input.withCString { inputPtr -> UnsafeMutablePointer<CChar>? in
            paper_parse(inputPtr)
        }
        guard let result = result else { return nil }
        defer { paper_string_free(result) }
        return String(cString: result)
    }
}

// C 函数声明
@_silgen_name("paper_parse")
private func paper_parse(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("paper_string_free")
private func paper_string_free(_ s: UnsafeMutablePointer<CChar>?)
```

#### 3.3 打通验证

**临时测试入口**（`App.swift`）：
```swift
@main
struct PaperStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    let html = PaperEngine.parse("@section{Hello} World")
                    print("HTML: \(html ?? "nil")")
                }
        }
    }
}
```

**验证**：
```bash
swift build
swift run PaperStudio
# 控制台应打印: HTML: <h1>Hello</h1>World...
```

---

### Day 5：双栏布局 + NSTextView 编辑器

#### 5.1 ContentView 双栏

**`Sources/PaperStudio/ContentView.swift`**：
```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var document = PaperDocument()

    var body: some View {
        HSplitView {
            EditorView(text: $document.source)
                .frame(minWidth: 400)
            PreviewView(html: document.html)
                .frame(minWidth: 400)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
```

#### 5.2 NSTextView 包装

**`Sources/PaperStudio/Editor/EditorView.swift`**：
```swift
import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditorView
        init(_ parent: EditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
```

#### 5.3 文档模型（带 debounce）

**`Sources/PaperStudio/Models/PaperDocument.swift`**：
```swift
import Foundation
import Combine

@MainActor
class PaperDocument: ObservableObject {
    @Published var source: String = ""
    @Published var html: String = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        // 默认示例，方便启动就能看到效果
        source = """
        @section{Hello Paper Studio}

        This is $E = mc^2$ inline math.

        $$$\\int_0^1 x dx$$$
        """

        $source
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] src in
                self?.html = PaperEngine.parse(src) ?? "<p>Parse error</p>"
            }
            .store(in: &cancellables)
    }
}
```

---

### Day 6：WKWebView 预览 + KaTeX 注入

#### 6.1 PreviewView

**`Sources/PaperStudio/Preview/PreviewView.swift`**：
```swift
import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let fullHTML = KaTeXInjector.wrap(html: html)
        webView.loadHTMLString(fullHTML, baseURL: Bundle.module.resourceURL)
    }
}
```

#### 6.2 KaTeX 注入

**`Sources/PaperStudio/Preview/KaTeXInjector.swift`**：
```swift
enum KaTeXInjector {
    static func wrap(html body: String) -> String {
        guard let katexCSS = loadResource("katex/katex.min.css"),
              let katexJS = loadResource("katex/katex.min.js"),
              let renderJS = loadResource("katex/contrib/auto-render.min.js") else {
            return body
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(katexCSS)</style>
        </head>
        <body>
        \(body)
        <script>\(katexJS)</script>
        <script>\(renderJS)</script>
        <script>renderMathInElement(document.body);</script>
        </body>
        </html>
        """
    }

    private static func loadResource(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil),
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

#### 6.3 KaTeX 资源拷贝

```bash
# 从 web/node_modules 拷（或下载）
mkdir -p PaperStudio/Sources/PaperStudio/Resources/katex
cp path/to/katex.min.css PaperStudio/Sources/PaperStudio/Resources/katex/
cp path/to/katex.min.js PaperStudio/Sources/PaperStudio/Resources/katex/
cp path/to/auto-render.min.js PaperStudio/Sources/PaperStudio/Resources/katex/contrib/
```

---

### Day 7：端到端验证 + 文档

#### 7.1 跑通测试用例

**手测脚本**（用以下 PaperML 输入逐个验证）：
```paper
@s1{Hello}

inline $E=mc^2$ math

block:
$$
\\int_0^1 x dx = 1/2
$$

@fig{path="cat.png" cap="A cat" label="fig:cat"}
@cite{vaswani2017}
```

**验证项**：
- [ ] 窗口 < 1s 启动
- [ ] 编辑时 200ms 内预览更新
- [ ] 行内 `$...$` 公式渲染
- [ ] 块级 `$$...$$` 公式渲染
- [ ] 公式无 NaN / unclosed 错误
- [ ] `swift build` 无 warning
- [ ] 应用包 < 50 MB

#### 7.2 写 Quick Start

**`PaperStudio/README.md`**：
- 如何 build：先 `cd paper-core && cargo build --release`，再 `cd ../PaperStudio && swift build`
- 如何 run：`swift run PaperStudio`
- 已知限制：仅 macOS 14+、仅 Apple Silicon（Phase 0）

---

## 三、Phase 0 验收（DoD）

满足以下全部条件，Phase 0 收尾：

| # | 项 | 验证方式 |
|---|---|---|
| 1 | SwiftPM 构建无 warning | `swift build` 退出码 0 + 无 warning |
| 2 | 启动 < 1 秒 | 手动 + `time swift run` |
| 3 | 双栏布局正常 | 拖动分割条，比例保留 |
| 4 | 编辑 PaperML 实时预览 | 输入文本 200ms 内右侧更新 |
| 5 | 行内 + 块级数学公式渲染 | KaTeX 正确显示 |
| 6 | 静态库链接无 leak | 长时间编辑（10 分钟）内存稳定 |
| 7 | 包大小 < 50 MB | `du -sh .build` |
| 8 | 代码提交 + 文档齐全 | git commit + README |

---

## 四、关键技术决策（Phase 0 范围）

| 决策 | 选型 | 原因 |
|---|---|---|
| 编辑器 | `NSTextView` 包装 | SwiftUI 原生 TextEditor 不够用；NSTextView 性能稳定 |
| 预览 | `WKWebView` | KaTeX 是 JS 库，必须 WebView |
| FFI 方式 | 手写头文件（暂） | cbindgen 推迟到 Phase 1，等引入 Diagnostic 再上 |
| Rust 调用约定 | `#[no_mangle] extern "C"` | 标准 C-ABI 跨语言 |
| 内存释放 | Rust 端 `into_raw` → Swift 调 `paper_string_free` | 避免 Swift 端 free 越界 |
| 项目管理 | SwiftPM（带 Xcode 兜底） | 轻量；Xcode 工程作为后备方案 |
| debounce | Combine `.debounce(200ms)` | 简单，编辑体验流畅 |

---

## 五、已知风险 + 应对

| 风险 | 应对 |
|---|---|
| SPM 链接 .a 文件路径问题 | 备选方案：直接用 Xcode 工程 |
| NSTextView 中文输入法卡顿 | Phase 0 不优化，记入 Phase 1 backlog |
| KaTeX 资源加载慢 | 内联到 HTML string，避免网络请求 |
| 跨架构（Intel / Apple Silicon） | Phase 0 只支持 arm64，Intel 编译 Phase 1 再说 |
| Rust panic 跨 FFI 边界 | Rust 端所有 FFI 函数包一层 `catch_unwind` |

---

## 六、Phase 0 → Phase 1 衔接

Phase 0 收尾后，进入 Phase 1（即原 Sprint 3-8），顺序：

1. Sprint 3：cbindgen + 错误诊断
2. Sprint 4-5：语法高亮 + 自动补全
3. Sprint 6：文件系统
4. Sprint 7：BibTeX
5. Sprint 8：导出 + 打磨

Phase 0 不做的事（明确边界）：
- ❌ 错误诊断（行号定位）
- ❌ 语法高亮
- ❌ 自动补全
- ❌ 文件系统 / Open / Save
- ❌ BibTeX
- ❌ HTML / PDF 导出
- ❌ 项目文件树 Sidebar

---

*文档版本：v0.1*
*创建日期：2026-08-01*

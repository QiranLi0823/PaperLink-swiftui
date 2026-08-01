# Paper Studio — SwiftUI 转型 Plan

> 调整背景：macOS 26 Gatekeeper 拦截未签名 Electron 应用，MVP 阶段转向 SwiftUI。
> 平台：macOS only
> 文档版本：v0.1
> 创建日期：2026-08-01

---

## 一、技术决策

| 维度 | 原方案（Electron） | 新方案（SwiftUI） |
|---|---|---|
| 平台 | macOS + Windows | **macOS only** |
| 编辑器 | Monaco Editor（Web） | SwiftUI `NSTextView` 包装 / `WKWebView + CodeMirror` |
| 核心引擎 | Rust → WASM | **Rust → 静态库 / C-ABI 桥接到 Swift** |
| 渲染 | HTML + KaTeX | **WKWebView 渲染 HTML 预览**（KaTeX 继续用 JS） |
| 包大小 | ~250 MB | ~20-40 MB |
| 启动 | 2-3s | <0.5s |

**关键决策**：`paper-core` Rust 完全保留，改用 **C-ABI**（`cbindgen` 生成头文件）导出，Swift 直接调 native 函数。
- Rust 的解析/渲染零损失
- SwiftUI 只做 UI 壳

---

## 二、项目结构

```
PaperLink/
├── paper-core/                 # Rust 引擎（保留，扩展 C-ABI 导出）
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs              # 添加 #[no_mangle] C 函数
│   │   ├── ast.rs
│   │   ├── parser.rs
│   │   ├── grammar.pest
│   │   └── renderer.rs
│   └── paper-core.h            # cbindgen 自动生成
│
├── PaperStudio/                # SwiftUI macOS 应用（新建）
│   ├── Package.swift
│   ├── PaperStudio.xcodeproj
│   ├── Sources/
│   │   └── PaperStudio/
│   │       ├── App.swift
│   │       ├── ContentView.swift
│   │       ├── Editor/
│   │       │   ├── EditorView.swift
│   │       │   ├── SyntaxHighlighter.swift
│   │       │   └── AutocompleteProvider.swift
│   │       ├── Preview/
│   │       │   ├── PreviewView.swift
│   │       │   └── KaTeXInjector.swift
│   │       ├── PaperCore/
│   │       │   ├── PaperEngine.swift
│   │       │   └── Diagnostics.swift
│   │       ├── FileSystem/
│   │       │   ├── ProjectManager.swift
│   │       │   └── FileWatcher.swift
│   │       ├── BibTeX/
│   │       │   └── BibParser.swift
│   │       ├── Export/
│   │       │   ├── HTMLExporter.swift
│   │       │   └── PDFExporter.swift
│   │       ├── Views/
│   │       │   ├── WelcomeView.swift
│   │       │   ├── Toolbar.swift
│   │       │   ├── Sidebar.swift
│   │       │   └── StatusBar.swift
│   │       └── Models/
│   │           ├── PaperDocument.swift
│   │           └── ParseResult.swift
│   ├── Resources/
│   │   ├── katex/
│   │   └── styles.css
│   └── Tests/
│
├── web/                        # 保留（Phase 0 demo）
├── examples/
└── doc_line/
```

---

## 三、Phase 1：8 个 Sprint（~10-12 周）

### Sprint 1：环境 + 最小可启动（1 周）

**目标**：SwiftUI 空白窗口能开，能调通 Rust 引擎

- [ ] 创建 `PaperStudio/Package.swift`
- [ ] `@main App` + 单窗口 `ContentView`（仅显示 "Paper Studio"）
- [ ] **paper-core 改成 `staticlib`**，`Cargo.toml` 加 `crate-type = ["staticlib", "rlib"]`
- [ ] 在 Swift 里用 `unsafe` 调用 Rust `parse_and_render`
- [ ] 测试：调用 Rust 函数 → 拿到 HTML 字符串 → 打印

**交付**：能在 Xcode / `swift run` 启动 macOS 窗口；Rust 引擎能跨语言调用。

### Sprint 2：双栏布局 + PaperML 编辑器（2 周）

**目标**：编辑 PaperML 能实时看到 HTML 预览

- [ ] 双栏 `HSplitView`：左编辑器 / 右预览
- [ ] 左侧：用 **`NSTextView` 包装**（SwiftUI `NSViewRepresentable`），支持语法高亮
  - 为什么不用 Monaco：Monaco 是 Web 的，SwiftUI 嵌入 WKWebView 太重
  - 短期方案：`NSTextView` + 简单正则高亮（`@section` 蓝色等）
  - 长期方案：考虑 `WKWebView + CodeMirror`（轻量，KaTeX 也能复用）
- [ ] 右侧：`WKWebView` 加载 HTML
- [ ] 编辑 → debounce 200ms → 调 Rust → 注入预览
- [ ] KaTeX 注入到预览

**交付**：MVP 双栏 IDE，能写 PaperML 看 HTML 预览。

### Sprint 3：Rust 引擎 C-ABI 化 + 错误诊断（1 周）

**目标**：解析错误能在 UI 显示行号

- [ ] `paper-core` 用 **cbindgen** 生成 `paper-core.h`
- [ ] 暴露 C 函数：
  ```c
  char* paper_parse(const char* input);                  // 返回 HTML
  void paper_parse_with_diagnostics(
      const char* input,
      PaperDiagnostic** out_diags,
      size_t* out_count,
      char** out_html
  );
  void paper_string_free(char* s);
  ```
- [ ] Swift 封装：`PaperEngine.swift` 把 C 字符串转 Swift `String`
- [ ] Swift 端把 `PaperDiagnostic { line, column, message }` 转成 UI 显示

**交付**：输入错的 PaperML，能在状态栏 / 编辑器行号标红显示错误位置。

### Sprint 4：PaperML 语法高亮（1 周）

**目标**：编辑器侧 PaperML 关键字着色

- [ ] 实现 `SyntaxHighlighter.swift`，基于 `NSTextView` 的 `layoutManager`
- [ ] 用正则匹配：
  - `@(section|figure|table|equation|cite|ref)` 关键字 → 蓝色
  - `$$...$$` / `$...$` 数学 → 绿色
  - `"..."` 字符串 → 红色
  - 注释 `//` → 灰色
- [ ] 编辑时实时刷新

**交付**：PaperML 源文件关键字有视觉区分。

### Sprint 5：自动补全（1 周）

**目标**：输入 `@fig` 弹出 `@figure{}` 片段

- [ ] 实现 `AutocompleteProvider.swift`
- [ ] 监听键盘 / 光标变化，弹出 NSPopover 候选列表
- [ ] 候选内容：
  - `@section Title`
  - `@figure{path = "..." caption = "..." label = "..."}`
  - `@table{caption = "..." columns = [...] rows = [...]}`
  - `@equation{content = "..." label = "..."}`
- [ ] Tab/Enter 插入片段，光标跳到第一个占位符

**交付**：写 PaperML 有片段补全。

### Sprint 6：文件系统 + 工程管理（2 周）

**目标**：能打开 / 保存 .pml 项目

- [ ] `ProjectManager.swift`：用 `NSOpenPanel` / `NSSavePanel`
- [ ] 项目结构：
  ```
  MyPaper/
  ├── paper.pml
  ├── figures/
  └── references.bib
  ```
- [ ] `FileWatcher.swift`：监听 `paper.pml` 变化，外部修改自动 reload
- [ ] Toolbar 加 "Open Project" / "Save" / "New Project" 按钮
- [ ] Sidebar 显示项目文件树（SwiftUI `OutlineGroup`）

**交付**：能打开本地 .pml 文件，编辑后保存，下次启动恢复。

### Sprint 7：BibTeX 支持（1 周）

**目标**：解析 `.bib` + `@cite{}` 补全

- [ ] `BibParser.swift`：用正则实现基础 BibTeX 解析（@article / @book / @inproceedings）
- [ ] 加载项目时读 `references.bib`
- [ ] Sidebar "References" 列出所有条目
- [ ] 编辑器 `@cite{` 触发补全：列出所有 bib key
- [ ] 预览中 `@cite{vaswani2017}` 显示为 `[vaswani2017]`

**交付**：能维护 references.bib + 自动补全。

### Sprint 8：HTML / PDF 导出 + 打磨（2 周）

**目标**：能导出独立 HTML 和 PDF

- [ ] `HTMLExporter.swift`：完整 HTML（CSS 内联 + KaTeX 内联）
- [ ] `PDFExporter.swift`：`WKWebView.createPDF` 输出 PDF
- [ ] Toolbar "Export HTML" / "Export PDF" 按钮
- [ ] 启动画面、App 图标、应用名 `Paper Studio`
- [ ] 文档：Quick Start README

**交付**：完整可发布的 macOS 应用。

---

## 四、关键技术风险

| 风险 | 影响 | 对策 |
|---|---|---|
| NSTextView 性能 | 大文件卡顿 | 超过 10K 行换 WKWebView + CodeMirror |
| cbindgen 自动生成 | 头文件管理复杂 | CI 加 cbindgen step；头文件 commit 进 repo |
| KaTeX 静态打包 | 资源加载慢 | 用 `Bundle.module` 嵌入，HTTP cache |
| Swift / Rust FFI 内存 | leak / crash | C 函数统一用 `paper_string_free` 释放；Rust 端负责内存 |
| macOS 26 SwiftUI 兼容 | Xcode beta 不稳定 | 锁定 Xcode 16.x / Swift 5.10 |
| Xcode 工程复杂度 | SPM 不支持 .app bundle | 用 `swift build` + 自写 `make_app.sh`；或建 `.xcodeproj` |

---

## 五、Phase 2 后续

MVP 跑通后，SwiftUI 优势显现：
- 模板系统 → SwiftUI `Picker` 切换 IEEE/Nature 样式
- PDF 导出 → 用 `WKWebView.createPDF` + SwiftUI 预览面板
- iCloud 同步 → SwiftUI 集成 `CloudKit`
- Spotlight 索引 → NSExtension
- Continuity / Handoff → 系统 API

---

## 六、MVP 验收标准

Sprint 8 完成条件：

- [ ] `swift build` 无 warning
- [ ] `swift run PaperStudio` 启动 < 1 秒
- [ ] 能打开 `web/examples/demo.pml` 完整渲染
- [ ] 编辑 PaperML，预览 200ms 内更新
- [ ] 输入错误 PaperML，红线标记位置 + 信息
- [ ] `@figure{}` 触发片段补全
- [ ] `@cite{}` 触发 bib key 补全
- [ ] Save / Open 正常
- [ ] Export HTML 输出 standalone 文件
- [ ] Export PDF 排版正确
- [ ] 应用包大小 < 50 MB

---

## 七、立即可启动的动作

1. **删 `desktop/`**（Electron 那摊）
2. **创建 `PaperStudio/`** 目录 + SwiftPM `Package.swift`
3. **改 `paper-core/Cargo.toml`** 加 `staticlib` crate type
4. **加 cbindgen** 到 paper-core dev-dependencies
5. 开始 **Sprint 1**：空白 SwiftUI 窗口 + Rust FFI 调通

---

## 八、为何放弃 Electron

| 阻碍点 | 描述 |
|---|---|
| Gatekeeper 拦截 | macOS 26 上未签名 / 未 notarize 的 Electron.app 直接被拦截 |
| 临时签 bypass | `xattr -cr` + `codesign -` ad-hoc 签名仍触发警告 |
| 关 Gatekeeper 风险 | `spctl --master-disable` 全局生效，不适合长期方案 |
| 开发签名成本 | Apple Developer 账号 $99/year，MVP 阶段不必要 |

macOS 26 + Apple Silicon + 未签名 = 几乎无法分发 Electron 给普通用户。

---

*文档版本：v0.1*
*创建日期：2026-08-01*

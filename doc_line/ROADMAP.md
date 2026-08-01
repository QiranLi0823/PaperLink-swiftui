# Paper Studio — 阶段性规划

> 平台：macOS only
> 当前版本：v0.1 (Phase 0)
> 最近更新：2026-08-01

---

## 一、Phase 0 完成情况 ✅

### 当前能力

macOS SwiftUI 应用，双栏布局：

```
┌─────────────────┬─────────────────┐
│  PaperML 源     │   论文预览      │
│  (TextEditor)   │  (WKWebView)    │
│                 │                 │
│  demo.pml       │  完整 HTML 渲染  │
│  实时编辑       │  KaTeX 公式     │
│  200ms debounce │  200ms 后刷新   │
└─────────────────┴─────────────────┘
```

### 已实现的 PaperML 结构

| 语法 | AST 节点 | 渲染 |
|---|---|---|
| `@title{...}` | `TitleBlock` | 居中标题 + 作者列表 |
| `@author{...}` | `Author` | 名字 + 邮箱 + affiliation |
| `@footnote{...}` | `Footnote` | 标题下方脚注列表 |
| `@abstract{...}` | `AbstractBlock` | 灰色框 + keywords |
| `@section` / `@subsection` | `Section`（嵌套 children） | h2/h3 + 缩进 |
| `@figure{...}` | `Figure` | `<img>` 或占位框 |
| `@table{...}` | `Table` | 真实 HTML 表格 |
| `@equation{...}` | `Equation` | KaTeX 块级渲染 |
| `@cite{key}` | `Inline.citation` | 角标 `[1]` + key 名 |
| `@ref{label}` | `Inline.reference` | 角标编号 |
| `$...$` 行内数学 | `Inline.math` | KaTeX 行内渲染 |

### 已修复的关键问题

- ✅ WKWebView 在 App Sandbox 下不渲染（关掉 sandbox + hardened runtime）
- ✅ subsection 嵌套父 section（AST 加 children + Parser 栈嵌装 + Renderer 递归）
- ✅ `$...$` 行内数学解析（KaTeX CDN 渲染）
- ✅ `@author` / `@footnote` 前缀匹配失败
- ✅ `@footnote` 块最后裸文本误解析为 KV
- ✅ author 脚注符号（note 字段映射 marker）

---

## 二、技术架构（当前）

```
PaperLink-swiftui/
├── README.md
├── examples/
│   └── demo.pml                    # PaperML 示例
├── doc_line/
│   └── ROADMAP.md                  # 本文档
└── PaperLink/PaperLink/
    ├── PaperLinkApp.swift          # @main 入口
    ├── ContentView.swift           # HSplitView 双栏 + WKWebView 包装
    ├── Models/
    │   └── PaperDocument.swift     # @MainActor 状态 + 200ms debounce
    ├── PaperCore/
    │   ├── PaperMLAST.swift        # AST 节点定义
    │   ├── PaperMLParser.swift     # 纯 Swift 解析器
    │   └── HTMLRenderer.swift      # ASTVisitor 转 HTML（含 KaTeX CDN）
    └── Resources/
        └── demo.pml               # Bundle 内副本
```

### 数据流

```
demo.pml (Bundle)
    ↓ PaperDocument.loadInitialSource()
    ↓ PaperMLParser.parse() [debounce 200ms]
PaperMLDocument AST
    ↓ HTMLRenderer.render() [ASTVisitor]
HTML 字符串（含 KaTeX CDN）
    ↓ WKWebView.loadHTMLString(baseURL=Bundle.resourceURL)
论文样式预览
```

---

## 三、Phase 1 方向

### P0（必须）

| # | 功能 | 说明 |
|---|---|---|
| 1 | 解析错误诊断 | 解析失败时显示 line/column + 错误信息（状态栏 + 编辑器红线） |
| 2 | 文件 Open / Save | NSOpenPanel / NSSavePanel，能打开 / 保存 `.pml` 文件 |
| 3 | Sandbox entitlement 重设计 | 正式分发前研究 WKWebView 在 sandbox 下的正确 entitlement |

### P1（应该）

| # | 功能 | 说明 |
|---|---|---|
| 4 | 语法高亮 | `@section` 蓝色、`@cite` 红色、公式绿色等（基于 NSTextView） |
| 5 | 自动补全 | `@fig` → `@figure{}` 片段补全 |
| 6 | HTML / PDF 导出 | 独立 HTML（含 KaTeX 内联）+ PDF（WKWebView.createPDF） |

### P2（可选）

| # | 功能 | 说明 |
|---|---|---|
| 7 | BibTeX 解析 | 加载 `.bib`，`@cite{` 触发 bib key 补全 |
| 8 | LaTeX 导出 | 复用 PaperML AST，写新 LaTeXRenderer |
| 9 | Docx 导出 | 复用 PaperML AST，写新 DocxRenderer |
| 10 | 项目文件树 Sidebar | SwiftUI `OutlineGroup` 显示项目结构 |
| 11 | 文件监听 | 外部修改自动 reload |

---

## 四、关键技术决策记录

| 决策 | 选择 | 原因 |
|---|---|---|
| 引擎 | 纯 Swift，不接 Rust | 之前 paper-core Rust 工具链版本冲突（LLVM 22 vs Apple 旧 nm），索性删掉 |
| 解析 | 手写而非 parser combinator | demo.pml 结构相对固定，手写够用；后续如要扩 grammar 再考虑 pest / swift-parsing |
| 渲染 | WKWebView + HTML | 比 SwiftUI 原生渲染能力（Text + AttributedString）强；公式走 KaTeX |
| KaTeX | CDN 而非本地 | 简化，无需 npm 步骤；离线时降级（公式显示原文） |
| Sandbox | Phase 0 关掉 | WKWebView helper 进程被 sandbox 拦截；正式分发要重新设计 |
| AST | struct + enum | 简单，零依赖；为未来 LaTeX / Docx 导出铺路 |

---

## 五、已知局限（Phase 0 不修）

| # | 局限 | 影响 | 计划 |
|---|---|---|---|
| 1 | 解析错误吞掉无报错 | 调试体验差 | Phase 1 P0 |
| 2 | 没 Position / Span | 报错没法指回源码位置 | Phase 1 P0 |
| 3 | `@ref` 动态编号 `[1][2]` | 学术论文习惯 `Fig. 1` / `Tab. 2` | Phase 1 P1 |
| 4 | 解析器单遍、不容错 | 一个 typo 整段挂掉 | Phase 1 P0 |
| 5 | KaTeX 加载延迟（CDN ~5s） | 首次打开慢 | 可选本地化 |
| 6 | 关掉 sandbox | 不符合 Mac App Store 分发要求 | 正式发布前必须修 |

---

## 六、时间线

- **2026-08-01**：Phase 0 完成（双栏 + 解析 + 渲染 + KaTeX）
- 后续：按 Phase 1 P0 → P1 → P2 顺序推进

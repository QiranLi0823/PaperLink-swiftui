# PaperLink

macOS SwiftUI 论文编辑器。Phase 0。

## 当前状态

启动时加载 `Resources/demo.pml`（论文示例，~145 行 PaperML）到左侧，右侧用 WKWebView 实时渲染为论文样式 HTML。

### 支持的 PaperML 语法

```
@title{
  @title = "..."
  @author{
    @name = "..."
    @affiliation = "..."
    @email = "..."
    @orcid = "..."
    @note = "equal_contribution"
  }
  @author{ ... }
  @footnote{
    @marker = "†"
    @label = "..."
    bare text here
  }
}

@abstract{
  @keywords = ["...", "..."]
  abstract paragraph text...
}

@section Title              ← 一级章节（h2）
@subsection Subtitle        ← 二级章节（h3，嵌进 @section 的 children）

@figure{
  @path = "figures/x.png"
  @caption = "..."
  @label = "fig:x"
}

@table{
  @caption = "..."
  @columns = ["...", "..."]
  @rows = [["...", "..."], ...]
}

@equation{
  @content = "\\hat{Y} = f_\\theta(X)"
  @label = "eq:framework"
}

正文段落中可以用：
  @cite{key}    → 行内角标 [1] + key 名
  @ref{label}   → 角标编号
  $E = mc^2$    → KaTeX 行内数学
```

**字段命名**：所有字段前缀 `@`，包括 `@title` 块内的 `title` 字段也写成 `@title`。

### 渲染

- 标题居中 + 作者列表（含 affiliation、email、corresponding * 标记）
- Abstract 灰色背景框 + keywords
- 一级 / 二级章节嵌套（subsection 缩进嵌入父 section）
- 段落两端对齐，行内 `@cite` 红角标
- `@figure` 真图渲染（图放 `PaperLink/Resources/figures/`）
- `@table` 真实 HTML 表格
- `@equation` + `$...$` 行内数学——KaTeX CDN 渲染
- 200ms debounce 实时刷新

## 不做什么（明确边界）

- ❌ 不接 Rust 引擎（纯 Swift 解析）
- ❌ 不接文件 I/O（Open / Save）
- ❌ 不接语法高亮 / 自动补全
- ❌ 不接 BibTeX
- ❌ 不接 HTML / PDF 导出
- ❌ 错误诊断不完善（容错但不会高亮语法错位置）

## 运行

```bash
open PaperLink/PaperLink.xcodeproj
# Xcode 里 ⌘R
```

要求：macOS 14+ / Xcode 16+

首次运行需要联网拉 KaTeX CDN。

## 目录结构

```
PaperLink-swiftui/
├── README.md
├── examples/
│   └── demo.pml                         # 论文示例源
├── doc_line/
│   └── ROADMAP.md                       # 阶段性规划
└── PaperLink/
    └── PaperLink/
        ├── PaperLinkApp.swift           # @main 入口
        ├── ContentView.swift            # HSplitView 双栏 + WKWebView 包装
        ├── Assets.xcassets/
        ├── Models/
        │   └── PaperDocument.swift      # @MainActor + Combine debounce
        ├── PaperCore/
        │   ├── PaperMLAST.swift         # AST 节点定义
        │   ├── PaperMLParser.swift      # 纯 Swift 解析器（含容错）
        │   └── HTMLRenderer.swift       # ASTVisitor → HTML + KaTeX CDN
        └── Resources/
            └── demo.pml                 # Bundle 内副本（启动加载）
```

## 已知问题

- **App Sandbox 已关闭**：Phase 0 简化。WKWebView 在 sandbox 下不渲染 helper 进程。正式分发需重新设计 entitlement。
- **容错有限**：删大括号、删 `@` 关键字等破坏性编辑会让 AST 节点变空，但不会崩溃。严重破坏（如删整个 `}`）会让整段解析失败。
- **KaTeX CDN 延迟**：首次打开 ~5s 加载，之后缓存。
- **demo.pml 必须用 ASCII 直引号 `"`**：弯引号 `""` 也支持但兼容性需测。

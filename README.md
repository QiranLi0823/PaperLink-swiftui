# PaperLink

macOS SwiftUI 论文编辑器。

## 当前状态

启动时加载**上次打开的 PaperML 文件**（若无则加载 `Resources/demo.pml`）到左侧，右侧用 WKWebView 实时渲染为论文样式 HTML。

支持 Open / Save / Save As / Rename（⌘O / ⌘S / ⌘⇧S / ⌘R）。左侧编辑器带**行号 + 错误行红底高亮**，底部状态栏显示解析错误数量。

## 支持的 PaperML 语法

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

## 渲染

- 标题居中 + 作者列表（含 affiliation、email、corresponding * 标记）
- Abstract 灰色背景框 + keywords
- 一级 / 二级章节嵌套（subsection 缩进嵌入父 section）
- 段落两端对齐，行内 `@cite` 红角标
- `@figure` 真图渲染（图放 `PaperLink/Resources/figures/`）
- `@table` 真实 HTML 表格
- `@equation` + `$...$` 行内数学——KaTeX CDN 渲染
- 200ms debounce 实时刷新

## 编辑器功能

- **行号 gutter**：左侧 44pt 灰色条带，行号右对齐
- **错误行红底**：`parseWithErrors` 报告的 ParseError 行号在 gutter 内画红底 + 行号变红
- **文件名紧凑 toolbar**：顶部只显示当前文件名，未保存时旁边红点
- **点击文件名重命名**：触发内联 TextField 编辑
- **持久化**：上次打开的文件路径存到 `UserDefaults[PaperLink.lastOpenedFilePath]`

## 不做什么（明确边界）

- ❌ 不接 Rust 引擎（纯 Swift 解析）
- ❌ 不接语法高亮 / 自动补全
- ❌ 不接 BibTeX
- ❌ 不接 HTML / PDF 导出
- ❌ 不接 sandbox / entitlements（已关闭）

## 运行

```bash
open PaperLink/PaperLink.xcodeproj
# Xcode 里 ⌘R
```

要求：macOS 14+ / Xcode 16+。

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
        ├── PaperLinkApp.swift           # @main 入口 + File 菜单
        ├── ContentView.swift            # HSplitView 双栏 + 紧凑 toolbar
        ├── Assets.xcassets/
        ├── Models/
        │   └── PaperDocument.swift      # @MainActor + Combine debounce + 文件 I/O
        ├── PaperCore/
        │   ├── PaperMLAST.swift         # AST 节点定义
        │   ├── PaperMLParser.swift      # 纯 Swift 解析器（parseWithErrors 报错）
        │   ├── ParseError.swift         # ParseError + ParseResult + String.offset→line/col
        │   └── HTMLRenderer.swift       # AST → HTML + KaTeX CDN
        ├── Editor/
        │   └── LineNumberedEditor.swift # NSTextView 包装 + GutterView 行号
        ├── FileSystem/
        │   └── ProjectManager.swift     # NSOpenPanel / NSSavePanel + UTF-8 I/O
        └── Resources/
            ├── demo.pml                 # Bundle 内副本（首次启动加载）
            └── figures/                 # demo 引用的图
```

## 已知问题

- **App Sandbox 已关闭**：Phase 1 简化。WKWebView 在 sandbox 下不渲染 helper 进程。正式分发需重新设计 entitlement。
- **解析容错有限**：5 种错误检测（缺 title/abstract、孤立 @author、@footnote 无 title footnote、未知关键字/字段）。删大括号、删 `@` 等破坏性编辑不会崩溃但可能漏报。
- **KaTeX CDN 延迟**：首次打开 ~5s 加载，之后缓存。
- **demo.pml 必须用 ASCII 直引号 `"`**：弯引号 `""` 也支持但兼容性需测。
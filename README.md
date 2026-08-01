# PaperLink

macOS SwiftUI 文本编辑器。当前状态：双栏 PaperML 解析预览。

## 当前能做什么

- 启动时加载 `Resources/demo.pml` 到左侧
- 左侧 `TextEditor` 编辑 PaperML 源
- 右侧 `AttributedString` 实时显示解析结果（200ms debounce）
- 5 个核心标签彩色高亮：
  - `@section` 蓝
  - `@figure` 绿
  - `@table` 紫
  - `@equation` 橙
  - `@cite{...}` 红 + 下划线，显示为 `[key]`

## 不做什么（明确边界）

- ❌ 不接 Rust 引擎（纯 Swift 解析）
- ❌ 不接 KaTeX / HTML 渲染
- ❌ 不接文件 I/O（Open / Save）
- ❌ 不处理 `demo.pml` 里的 `@title` / `@author` / `@subsection` / `@ref` / `$...$`（当文本）

## 运行

```bash
open PaperLink/PaperLink.xcodeproj
# Xcode 里 ⌘R
```

要求：macOS 14+ / Xcode 16+

## 目录

```
PaperLink-swiftui/
├── README.md
├── examples/
│   └── demo.pml                       # 源 PaperML
└── PaperLink/
    └── PaperLink/
        ├── PaperLinkApp.swift          # @main 入口
        ├── ContentView.swift           # HSplitView 双栏 + AttributedString
        ├── Assets.xcassets/
        ├── Models/
        │   └── PaperDocument.swift     # @MainActor + Combine debounce
        ├── PaperCore/
        │   └── PaperMLParser.swift     # 5 标签解析器
        └── Resources/
            └── demo.pml               # Bundle 内副本
```

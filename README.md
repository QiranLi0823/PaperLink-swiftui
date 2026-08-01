# PaperLink

macOS SwiftUI 论文编辑器。

## 当前状态

启动时加载**上次打开的 PaperML 文件**（若无则加载 `Resources/demo.pml`），左侧 editor，右侧 WKWebView 实时渲染为论文样式 HTML。窗口左侧可选 **sidebar**（项目文件树 / 图片列表），用标题栏的两个 icon 按钮切换模式，再点同一个按钮收起。

支持 Open / Save / Save As / Rename / Open Recent（⌘O / ⌘S / ⌘⇧S / ⌘R）。左侧编辑器带**行号 + 错误行红底高亮 + @identifier 蓝色高亮**。editor 与 preview 之间用 **NSSplitViewController** 拆，可拖动分隔条 + 比例持久化。窗口标题显示当前文件名，脏状态时附加 `*` 标记；关闭未保存的文件会弹"是否保存"对话框。

Release build 启用 **App Sandbox + hardened runtime**，通过 `scripts/notarize.sh` 可执行 Apple 公证。Dev build 使用空 entitlements 避免 sandbox 干扰开发体验。

File 菜单下新增 **Settings…**（⌘,），弹出 macOS 玻璃感卡片：左侧 sidebar 切换 Preferences / About，Preferences 含主题切换（跟随系统 / 深色 / 浅色），About 含技术栈和开发者邮箱。

## 布局

- **三栏**：sidebar（条件渲染，可隐藏）+ editor（minWidth 380）+ preview（minWidth 380）
- **editor / preview 1:1**：NSSplitViewController，splitter 可拖动，比例写到 `UserDefaults[PaperLink.splitFraction]`
- **sidebar 切换**：标题栏两个 icon 按钮（📁 项目 / 🖼 图片），再点同一项收起整个 sidebar
- **窗口标题**：当前文件名 + `*`（未保存）；未打开文件时显示 `Untitled.pml`

## Sidebar 状态机

`SidebarState.activeMode: Mode?` 单一状态，三态切换：

| 当前状态 | 点击 📁 | 点击 🖼 |
|---|---|---|
| `.project` (1, 0) | 收起 (`nil`) | 切到 `.figures` |
| `.figures` (0, 1) | 切到 `.project` | 收起 (`nil`) |
| `nil` (0, 0) | 展开 `.project` | 展开 `.figures` |

收起时两个按钮都显示次要色（无选中态），符合 (0, 0) 视觉。

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
- Abstract 圆角背景框 + keywords
- 一级 / 二级章节嵌套（subsection 缩进嵌入父 section）
- 段落两端对齐，行内 `@cite` 蓝色角标
- `@figure` 真图渲染——**图片根目录 = 当前 .pml 所在目录**：
  - 用户文档：`~/Documents/papers/demo2.pml` 同目录下的 `figures/` 子目录（图路径 `figures/x.png`）
  - bundle 内 demo：`Bundle/Resources/figures/`
- `@table` 真实 HTML 表格（圆角 + 斑马头）
- `@equation` + `$...$` 行内数学——KaTeX CDN 渲染
- 200ms debounce 实时刷新
- **CSS variables**：自动适配 macOS 深色模式
- **WKWebView 加载策略**：HTML 写到 `.pml` 同目录的 `.paperlink-preview-<hash>.html`，`loadFileURL(allowingReadAccessTo: rootURL)` 加载。
  关键：HTML 文件必须在 rootURL **之内**，否则 WKWebView sandbox 会拒绝初始化（`url is not inside resource directory url`）。

## 编辑器功能

- **行号 gutter**：左侧 32pt 灰色条带，行号右对齐，monospaced digit font
- **错误行高亮**：`parseWithErrors` 报告的 ParseError 行号在 gutter 内画红色 10% 背景 + 左侧 2pt 红条，行号变红
- **行号定位**：按 visual line 渲染——一段被软换行拆成 N 行的文字，行号只画在第一行顶部，后续视觉行只画错误底色（不重复行号）
- **多色语法高亮（Sprint 8.1）**：四种 token 各自颜色——`@identifier` accentColor 蓝、`"..."` 字符串 systemGreen 绿、`\d+` 数字 systemOrange 橙、`//` 注释 secondaryLabelColor 灰；`@identifier` 涂色跳过字符串/注释内部范围避免误涂
- **自动闭合 + 智能缩进（Sprint 8.2）**：敲 `{[("` 自动加闭合字符 + 光标居中；回车在 `{}` 之间自动插入对齐换行；普通回车保持当前行行首缩进；通过 `NSTextViewDelegate.textView(_:shouldChangeTextIn:replacementString:)` 拦截
- **gutter 跳行 + 当前行高亮（Sprint 8.3）**：点击 gutter 行号 → textView 选中整行 + 滚动到可见；监听 `NSTextView.didChangeSelectionNotification` 实时更新当前行高亮（左侧 2pt accent 条 + 6% accent 背景）
- **⌘F 查找（Sprint 8.4）**：顶部悬浮 FindBar 毛玻璃卡，输入实时匹配 + 系统黄色 `findHighlightColor` 背景高亮；⌘G / ⇧⌘G 跳下一个/上一个 + `showFindIndicator(for:)` 黄色聚焦框；ESC 关闭；通过 NotificationCenter 跨 SwiftUI/NSViewRepresentable 通信
- **跟随光标（Sprint 9）**：toolbar 第三个按钮（`arrow.left.arrow.right.square`），开启后编辑器选区变化时自动算 anchor（光标行 → `(kind, index, progress)` 三元组），通过 `paperLinkFollowCursorAnchor` 通知推给 `WKWebView`，调用 `window.scrollToBlock(kind, index, progress)` 滚动预览内容到对应 DOM 节点；关闭按钮立即停止同步。off → on 时会**主动触发一次刷新**（不等下一次 selectionChanged），让 preview 立即滚到当前光标位置。详见下节「[跟随光标实现细节](#跟随光标实现细节)」。
- **持久化**：上次打开的文件存为 security-scoped bookmark（`UserDefaults[PaperLink.lastOpenedBookmark]`）；最近文件列表存书签数组（`UserDefaults[PaperLink.recentBookmarks]`）
- **重命名**：⌘R 触发同目录下重命名（移动文件 + 更新持久化路径）
- **Finder 双击 / 命令行 `open file.pml`**：通过 `.onOpenURL` 把传入 URL 转给 `document.open(url:)`，实现文件类型关联的端到端打通
- **现代 CSS**：HTMLRenderer 使用 CSS variables，自动适配 light/dark mode；body `max-width: 100%` + `overflow-x: hidden` 防止 WKWebView 在窄容器内横向溢出

## 跟随光标实现细节

> **目标**：编辑器光标行变化时，右侧预览自动滚到对应渲染节点，并把节点中央对齐到视窗中央。

### 数据流

```
┌─────────────────┐    50ms debounce     ┌──────────────────────────┐
│ NSTextView      │ ───────────────────▶ │ EditorSplitViewController │
│ didChangeSel    │  cursor line         │  PaperMLLayout.anchor()  │
└─────────────────┘                      │  → (kind, index, prog)   │
                                         └────────────┬─────────────┘
                                                      │ NotificationCenter
                                                      ▼
                                         ┌──────────────────────────┐
                                         │ HTMLPreview.Coordinator  │
                                         │  → evaluateJavaScript    │
                                         └────────────┬─────────────┘
                                                      │ JS
                                                      ▼
                                         ┌──────────────────────────┐
                                         │ window.scrollToBlock()   │
                                         │  → querySelector         │
                                         │  → getBoundingClientRect │
                                         │  → window.scrollTo       │
                                         └──────────────────────────┘
```

### 关键模块

- **`PaperMLLayout`**：把 PaperML source 切成布局 block（kind + startLine/endLine + indexInKind + 行级 progress），光标行二分查表落到对应 block。`@figure` / `@table` / `@equation` 用 brace-depth 配对算真实 endLine（紧跟的 paragraph 段不会被吞进 brace 块）。
- **`EditorSplitViewController`**：监听 `NSTextView.didChangeSelectionNotification` → 50ms debounce → 算 anchor → 通过 `paperLinkFollowCursorAnchor` 通知 broadcast。
- **`AnchorProvider` 单例**：桥接 Editor ↔ Preview，因为 `HTMLPreview` 是 `NSViewRepresentable`，SwiftUI 不感知 reference-type 变化，所以 Editor 端写 `AnchorProvider.shared.current`，Preview 端的 `Coordinator` 直接观察 `paperLinkFollowCursorAnchor` 通知并立刻 `evaluateJavaScript`（绕过 SwiftUI 的 diff）。
- **`HTMLPreview` userScript**：在 `atDocumentStart` 注入 `window.scrollToBlock(kind, index, progress)`，内部用 `[data-block-kind][data-block-index]` 选节点、`getBoundingClientRect()` 算真实渲染 y；挂 `MutationObserver` + `ResizeObserver` + `load` 事件做延迟 reapply（KaTeX 异步渲染后高度变化时重滚）。

### 微抖动处理

- **行级 progress**：anchor 在 block 内按 `line - startLine / endLine - startLine` 算进度，preview 端用 `rect.top + progress * rect.height` 算目标 y，避免 1 个 block 多行时一直停在同一位置。
- **50px 死区**：`Math.abs(delta) < 50` 直接 `return true`（不滚），避免相邻行（小间距 block 间切换）时的视觉抖动。
- **空行 fallback**：光标行不在任何 block 内时 fallback 到"前一个 block 末尾"（progress=1），而非 `blocks.last`（避免预览滚到底）。

### 索引对齐

PaperMLLayout 和 HTMLRenderer **各自独立数** paragraph / table / figure 的 indexInKind，必须严格对齐：

- 顶层 `paragraph` block 不能数到 `@title{...}` 内部的内容（L2 / L30 / L36 等）
- `@table` / `@figure` 的 endLine 必须用 brace-depth 配对，不能用"下一个 top-level header"（否则 L115 paragraph 会被吞进 L103-L117 的 table 块）
- `@title` / `@author` / `@footnote` 嵌套 brace 让 `blockEndByNextHeader` 仍然适用

### 开关状态门控

跟随光标按钮关闭时 preview **不能**跟随——这条不变量由两道 gate 守护：

- **源头节流**：`LineNumberedEditor.postFollowCursorFraction` 检查 `followCursorMode`，关闭时直接 `return`，不算 anchor / 不 post 通知 / 不触发 editor 自身滚动
- **Coordinator 守门**：`HTMLPreview.Coordinator.onFollowCursorAnchor` 也检查一次（`defense-in-depth`，防止别处误发通知时 preview 失控）

### off → on 主动刷新

按钮从 off → on 时 `PreviewPaneContent.onChange` post `paperLinkFollowCursorEnabled` 通知，`LineNumberedEditor.Coordinator` 收到后**绕过 50ms debounce** 立即调 `postFollowCursorFraction`，让 preview 瞬间滚到当前光标位置。

### 可观测性

开启「跟随光标」后控制台会持续打两行日志（生产可保留）：

```
[FollowCursor] line=119 → anchor kind=paragraph index=10 progress=0.0
[FollowCursor/JS] {"ok":true,"target":"paragraph","index":10,"progress":0,"scrollY":3408,"scrollHeight":4980,"viewportH":855,"blockCount":14}
```



## Open Recent

File 菜单下 "Open Recent" 子菜单，最近 10 个 `.pml` 文件，存为 security-scoped bookmark（sandbox 跨启动恢复用）。支持 "Clear Menu"。

## Settings（Sprint 7-9）

File 菜单下 "Settings…"（⌘,）弹出 720×480 macOS 玻璃感卡片：

- **窗口材质**：`NSVisualEffectView` material=`.popover` + state=`.active`，真实 vibrancy 玻璃，跟随系统深/浅
- **左侧 sidebar**：悬浮圆角矩形，顶部 PaperLink brand logo，"Settings" 分组标题，列表项左侧 2pt accent 高亮条 + 选中态 accent 填充
- **Preferences 面板**：22pt 大标题 + 副标题，主题 segmented 三选一切换器（跟随系统 / 深色 / 浅色）
- **About 面板**：渐变 app logo 卡片 + 彩色 icon 技术栈列表（SwiftUI / PaperML / WKWebView / Sandbox / UTI）+ 开发者邮箱卡片

**主题**：单例 `ThemeManager`，首次启动默认跟随 macOS 系统外观；选 explicit 深/浅色 → 覆盖所有窗口 appearance；选"跟随系统" → 清掉所有 override，窗口实时跟随系统在控制中心切换深/浅。

**弹出位置**：每次 show() 用 `setFrame` 算 PaperLink 主窗口中心，panel 居中到主窗口（不是屏幕中心），并 clamp 到主窗口所在屏幕 visibleFrame 内——多屏 / dock 都不会让 Settings 跳到错位置。

## 文件类型关联

注册了自定义 UTI `com.paperlink.pml`（conforms to `public.plain-text` / `public.text`）：

- **扩展名**：`.pml`
- **MIME**：`text/x-paperml`
- **角色**：Editor（rank=Owner）
- **配置位置**：`PaperLink/PaperLink/Info.plist`（`UTExportedTypeDeclarations` + `CFBundleDocumentTypes`），通过 `INFOPLIST_FILE` build setting 关联，关闭 Xcode 自动生成

Finder 右键 `.pml` 文件 → "Open With" 应出现 PaperLink；双击会启动并加载文件。

## 安全与分发（Sprint 7）

Release build：

- **App Sandbox**：开启（`com.apple.security.app-sandbox = true`）
- **Hardened Runtime**：开启
- **Entitlements**：sandbox + `files.user-selected.read-write` + `files.bookmarks.app-scope` + `network.client`
- **公证脚本**：`scripts/notarize.sh`（xcodebuild archive → ditto zip → notarytool submit --wait → stapler）

Dev build（`ENABLE_APP_SANDBOX = NO`）使用 `PaperLink-Dev.entitlements`（空），保留所有便利行为（任意位置读 .pml 同目录 figures/、自由保存临时 HTML 等）。

## 不做什么（明确边界）

- ❌ 不接 Rust 引擎（纯 Swift 解析）
- ❌ 不接自动补全 / LSP
- ❌ 不接 BibTeX
- ❌ 不接 HTML / PDF 导出
- ❌ 不接多 tab

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
├── scripts/
│   └── notarize.sh                      # xcodebuild archive + notarytool + stapler
└── PaperLink/
    └── PaperLink/
        ├── PaperLinkApp.swift           # @main 入口 + File 菜单 + Open Recent + sidebar toolbar + WindowCloseGuard
        ├── ContentView.swift            # 三栏布局（sidebar + NSSplitViewController）+ HTMLPreview WKWebView
        ├── Info.plist                   # 自定义 plist：UTI 注册 + CFBundleDocumentTypes
        ├── PaperLink.entitlements       # Release：完整 sandbox + user-selected + bookmarks.app-scope + network.client
        ├── PaperLink-Dev.entitlements   # Debug：空（避免 sandbox 干扰开发）
        ├── Assets.xcassets/
        ├── Models/
        │   ├── PaperDocument.swift      # @MainActor + Combine debounce + security-scoped bookmark + 文件 I/O
        │   ├── SidebarState.swift       # sidebar 全局状态（activeMode: Mode? 单一状态）
        │   ├── ThemeManager.swift       # 全局主题单例（跟随系统 / 深 / 浅），写 NSApp.appearance
        │   ├── SettingsWindowController.swift  # Settings 玻璃感 NSPanel 单例
        │   └── WindowCloseGuard.swift   # NSWindow.willCloseNotification → "是否保存"对话框
        ├── PaperCore/
        │   ├── PaperMLAST.swift         # AST 节点定义
        │   ├── PaperMLParser.swift      # 纯 Swift 解析器（parseWithErrors 报错）
        │   ├── PaperMLLayout.swift      # Sprint 9：source → [Block] + anchor(atLine:) + 缓存
        │   ├── ParseError.swift         # ParseError + ParseResult + String.offset→line/col
        │   └── HTMLRenderer.swift       # AST → HTML + KaTeX CDN + modern CSS + data-block-* 锚点
        ├── Editor/
        │   ├── EditorSplitViewController.swift  # NSSplitViewController + 比例持久化（NSHostingController 包装 SwiftUI）
        │   ├── LineNumberedEditor.swift # NSTextView 包装 + GutterView 行号 + 多色高亮 + 自动闭合 + ⌘F 查找
        │   ├── FindBar.swift            # ⌘F 查找条（顶部浮窗 + 命中数 + prev/next）
        │   ├── SettingsView.swift       # Settings 卡片（3:2 圆角 + sidebar + segmented 主题切换）
        │   └── SidebarView.swift        # sidebar 容器（项目 / 图片）+ ProjectNavigatorView + FiguresGridView
        ├── FileSystem/
        │   ├── ProjectManager.swift     # NSOpenPanel / NSSavePanel + UTF-8 I/O
        │   └── ProjectTreeManager.swift # 扫描目录构建 FileNode 树
        └── Resources/
            ├── demo.pml                 # Bundle 内副本（首次启动加载）
            └── figures/                 # demo 引用的图
```

## 已知问题

- **@identifier 高亮只涂蓝色一种**：当前只区分关键字与正文，不区分字符串/数字/注释；后续如需再扩。
- **KaTeX CDN 延迟**：首次打开 ~5s 加载，之后缓存。
- **demo.pml 必须用 ASCII 直引号 `"`**：弯引号 `""` 也支持但兼容性需测。
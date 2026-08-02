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
- **语法高亮（Sprint 5）**：所有 `@identifier`（如 `@section`、`@author`、`@title`）涂成 accentColor（蓝色），其余字符保持默认 labelColor（dark mode 白 / light mode 黑）。监听 `NSTextDidChangeNotification` 在每次输入后重涂。
- **持久化**：上次打开的文件存为 security-scoped bookmark（`UserDefaults[PaperLink.lastOpenedBookmark]`）；最近文件列表存书签数组（`UserDefaults[PaperLink.recentBookmarks]`）
- **重命名**：⌘R 触发同目录下重命名（移动文件 + 更新持久化路径）
- **Finder 双击 / 命令行 `open file.pml`**：通过 `.onOpenURL` 把传入 URL 转给 `document.open(url:)`，实现文件类型关联的端到端打通
- **现代 CSS**：HTMLRenderer 使用 CSS variables，自动适配 light/dark mode；body `max-width: 100%` + `overflow-x: hidden` 防止 WKWebView 在窄容器内横向溢出

## Open Recent

File 菜单下 "Open Recent" 子菜单，最近 10 个 `.pml` 文件，存为 security-scoped bookmark（sandbox 跨启动恢复用）。支持 "Clear Menu"。

## Settings（Sprint 8-9）

File 菜单下 "Settings…"（⌘,）弹出 720×480 macOS 玻璃感卡片：

- **窗口材质**：`NSVisualEffectView` material=`.popover` + state=`.active`，真实 vibrancy 玻璃，跟随系统深/浅
- **左侧 sidebar**：悬浮圆角矩形，顶部 PaperLink brand logo，"Settings" 分组标题，列表项左侧 2pt accent 高亮条 + 选中态 accent 填充
- **Preferences 面板**：22pt 大标题 + 副标题，主题 segmented 三选一切换器（跟随系统 / 深色 / 浅色）
- **About 面板**：渐变 app logo 卡片 + 彩色 icon 技术栈列表（SwiftUI / PaperML / WKWebView / Sandbox / UTI）+ 开发者邮箱卡片

**主题**：单例 `ThemeManager`，首次启动默认跟随 macOS 系统外观；选 explicit 深/浅色 → 覆盖所有窗口 appearance；选"跟随系统" → 清掉所有 override，窗口实时跟随系统在控制中心切换深/浅。

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
        │   ├── ParseError.swift         # ParseError + ParseResult + String.offset→line/col
        │   └── HTMLRenderer.swift       # AST → HTML + KaTeX CDN + modern CSS
        ├── Editor/
        │   ├── EditorSplitViewController.swift  # NSSplitViewController + 比例持久化（NSHostingController 包装 SwiftUI）
        │   ├── LineNumberedEditor.swift # NSTextView 包装 + GutterView 行号 + @identifier 高亮
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
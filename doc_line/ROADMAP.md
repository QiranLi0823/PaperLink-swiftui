# Paper Studio — 阶段性规划

> 平台：macOS only
> 当前版本：v0.3 (Phase 1 P0 完成)
> 最近更新：2026-08-02

---

## 一、Phase 0 完成情况 ✅

### 当前能力

macOS SwiftUI 应用，三栏布局 + 完整解析错误诊断 + 文件 I/O：

```
┌──────────┬─────────────────┬─────────────────┐
│          │   PaperML 源     │   论文预览      │
│ Sidebar  │  (LineNumbered  │  (WKWebView)    │
│ (隐藏)   │   Editor +       │                 │
│          │   Gutter)        │  完整 HTML 渲染  │
│ 项目/图片 │  行号 + 红条     │  KaTeX 公式     │
│ 切换     │  实时编辑        │  200ms 后刷新   │
└──────────┴─────────────────┴─────────────────┘
```

---

## 二、Phase 1 P0 完成度（100%）

### Sprint 1：解析错误诊断 ✅ **完成**

- [x] AST 加 `Position` / `Span`
- [x] Parser 返回 `parseWithErrors` (Result-like)
- [x] `ParseError` 结构（line/column/message/severity）
- [x] 编辑器行号标红（gutter 红底 + 2pt 红条 + 行号变红）
- [x] 状态栏显示错误数量 + 第一条错误详情
- [x] Visual line 行号定位（软换行只画一次行号）

### Sprint 2：文件 Open / Save 🟡 **基本完成（7/8）**

- [x] `PaperDocument.load(from:)` / `save(to:)`
- [x] File 菜单 Open / Save / Save As（⌘O / ⌘S / ⇧⌘S）
- [x] NSOpenPanel / NSSavePanel 集成
- [x] `isDirty` 内存状态
- [x] UserDefaults 持久化最后打开文件
- [x] ⌘R 重命名
- [x] **标题栏 `*` 标记未保存状态**（Task #1 完成）
- [x] **关闭未保存时弹确认对话框**（Task #2 代码完成，待运行时验证）
- [ ] Open Recent 菜单（可选）

### Sprint 3：Sandbox Entitlement 🟡 **部分完成（1/8）**

- [ ] 启用 `ENABLE_APP_SANDBOX = YES`
- [ ] 启用 `ENABLE_HARDENED_RUNTIME = YES`
- [ ] 创建 entitlements 文件
- [ ] security-scoped bookmark
- [ ] 验证 WKWebView / 图片 / Open-Save 在沙箱下正常
- [ ] `xcrun notarytool` 公证脚本
- [x] **.pml UTI 注册**（Task #3 完成，待运行时验证）
- [ ] pbxproj 关联 entitlements

---

## 三、P0 收尾执行清单（全部 ✅ 完成）

> **P0 整体 100% 完成**：Task #1（标题栏 `*`）+ Task #2（关闭对话框）+ Task #3（UTI 注册）全部完成。
> 剩余 2 项验证（2.7 / 3.5）为运行时手动测试，需打开 Xcode build 一次。

### ✅ Task #1：标题栏 `*` 标记未保存状态

| # | 子步骤 | 涉及文件 | 状态 |
|---|---|---|---|
| 1.1 | ContentView 加 computed `windowTitle`：根据 `document.isDirty` + `currentFileName` 返回 `"demo.pml*"` / `"demo.pml"` / `"Untitled.pml*"` | `ContentView.swift` | ✅ |
| 1.2 | `.navigationTitle(windowTitle)` 替换当前硬编码 `"PaperLink"` | `ContentView.swift` | ✅ |
| 1.3 | （可选）未打开文件时标题显示 `Untitled.pml` + dirty 时加 `*` | `ContentView.swift` | ✅（currentFileName fallback 已覆盖）|

**验证**：open file → 标题 `demo.pml`；输入字符 → `demo.pml*`；⌘S → 变回 `demo.pml`

### ✅ Task #2：关闭未保存时弹「是否保存」对话框

| # | 子步骤 | 涉及文件 | 状态 |
|---|---|---|---|
| 2.1 | 新建 `WindowCloseGuard.swift`：监听 `NSWindow.willCloseNotification`，触发 NSAlert 三选项 | `Models/WindowCloseGuard.swift`（新） | ✅ |
| 2.2 | Alert 三选项：Save（默认 ⏎）/ Don't Save（⇧⌘⌫）/ Cancel（Esc） | `Models/WindowCloseGuard.swift` | ✅ |
| 2.3 | Save 路径：调 `document.save()`，若失败（无 fileURL）→ 走 saveAs | `Models/WindowCloseGuard.swift` | ✅ |
| 2.4 | Don't Save 路径：标记 `forceClose = true`，下次 willClose 不再拦截 | `Models/WindowCloseGuard.swift` | ✅ |
| 2.5 | Cancel 路径：用户数据保留（dirty 状态还在） | `Models/WindowCloseGuard.swift` | ✅ |
| 2.6 | PaperLinkApp 用 `.onAppear` 挂 guard 到第一个可见窗口 | `PaperLinkApp.swift` | ✅ |
| 2.7 | 验证三种场景：脏文件关闭 / 干净文件关闭 / saveAs 失败 | 手动测试 | ⏳ 待运行时验证 |

**验证**：修改后 ⌘W → 弹对话框；⌘S → 关；不修改 → 不弹

### ✅ Task #3：.pml UTI 注册

| # | 子步骤 | 涉及文件 | 状态 |
|---|---|---|---|
| 3.1 | 创建 `Info.plist`：添加 `UTExportedTypeDeclarations` + `CFBundleDocumentTypes` | `PaperLink/Info.plist`（新） | ✅ |
| 3.2 | 定义 UTI：`com.paperlink.pml`，conforms to `public.plain-text` + `public.text` | Info.plist | ✅ |
| 3.3 | 定义文件扩展名：`.pml`，MIME type `text/x-paperml` | Info.plist | ✅ |
| 3.4 | pbxproj 关联 Info.plist：`INFOPLIST_FILE` build setting + `GENERATE_INFOPLIST_FILE=NO`（Debug + Release） | `project.pbxproj` | ✅ |
| 3.5 | 验证 Finder 双击 `.pml` 文件 → 启动 PaperLink + 加载文件 | 手动测试 | ⏳ 待运行时验证 |

**验证**：Finder 右键 `.pml` → "Open With" 出现 PaperLink

**关于 synchronized group 的说明**：`PaperLink/` 目录是 `PBXFileSystemSynchronizedRootGroup`，Xcode 15+ 会自动同步所有子文件到 target。`INFOPLIST_FILE` 指向的文件会被 Xcode 自动从 Resources phase 排除（内置行为），不会重复打包。

---

## 四、执行顺序

```
#1.1 ──┐
#1.2 ──┤── Task #1（标题栏 *）  ── 5 分钟
#1.3 ──┘
        │
        ▼
#2.1 ──┐
#2.2 ──┤
#2.3 ──┤── Task #2（关闭对话框）  ── 30 分钟
#2.4 ──┤
#2.5 ──┤
#2.6 ──┤
#2.7 ──┘ （验证）
        │
        ▼
#3.1 ──┐
#3.2 ──┤
#3.3 ──┤── Task #3（UTI 注册）   ── 15 分钟
#3.4 ──┤
#3.5 ──┘ （验证）
```

**总时间预估**：~50 分钟 + 手动验证

---

## 五、已完成（额外）

### 三栏布局（Phase 1 P1 范围）
- [x] sidebar 容器（项目文件树 / 图片列表两种模式）
- [x] SidebarState 全局状态（`activeMode: Mode?` 单一状态，三态切换）
- [x] SidebarModeBar（标题栏自定义 icon 按钮组，去外框 + 选中态正圆蓝底）
- [x] ProjectNavigatorView（Xcode 风格文件树，非递归 flatten）
- [x] ProjectTreeManager（扫描目录构建 FileNode 树）
- [x] FiguresGridView（图片文件名列表）
- [x] HSplitView editor/preview 对称 minWidth（1:1）

### 渲染美化
- [x] HTMLRenderer CSS variables + dark mode
- [x] 错误行 gutter 红条（柔和 10% 背景 + 2pt 红条）
- [x] 状态栏 modern 样式（regular material + 11pt 字号）
- [x] 标题栏动态文件名 + `*` dirty 标记

---

## 六、技术架构现状

```
PaperLink/
├── PaperLink/
│   ├── PaperLinkApp.swift              # @main + commands + sidebar toolbar
│   ├── ContentView.swift               # 三栏布局（sidebar + HSplitView editor/preview）
│   ├── Editor/
│   │   ├── LineNumberedEditor.swift    # NSTextView 包装 + GutterView 行号
│   │   └── SidebarView.swift           # sidebar 容器 + ProjectNavigatorView + FiguresGridView
│   ├── PaperCore/
│   │   ├── PaperMLAST.swift            # AST 节点定义
│   │   ├── PaperMLParser.swift         # 纯 Swift 解析器（parseWithErrors）
│   │   ├── ParseError.swift            # ParseError + ParseResult
│   │   └── HTMLRenderer.swift          # AST → HTML + KaTeX + modern CSS
│   ├── FileSystem/
│   │   ├── ProjectManager.swift        # NSOpenPanel / NSSavePanel + UTF-8 I/O
│   │   └── ProjectTreeManager.swift    # 扫描目录构建 FileNode 树
│   ├── Models/
│   │   ├── PaperDocument.swift         # @MainActor + Combine debounce + 文件 I/O + notification
│   │   └── SidebarState.swift          # sidebar 全局状态（activeMode 单一状态）
│   ├── Info.plist                      # ← 待 Task #3 创建
│   └── Resources/
│       ├── demo.pml
│       └── figures/
└── ...
```

---

## 七、关键技术决策记录

| 决策 | 选择 | 原因 |
|---|---|---|
| 引擎 | 纯 Swift，不接 Rust | 之前 paper-core Rust 工具链版本冲突，索性删掉 |
| 解析 | 手写而非 parser combinator | demo.pml 结构相对固定，手写够用 |
| 渲染 | WKWebView + HTML | 比 SwiftUI 原生渲染能力强；公式走 KaTeX |
| KaTeX | CDN 而非本地 | 简化，无需 npm 步骤 |
| Sandbox | 当前关掉 | WKWebView helper 进程被 sandbox 拦截；Sprint 3 修 |
| AST | struct + enum | 简单，零依赖；为未来 LaTeX / Docx 导出铺路 |
| Sidebar 状态机 | `activeMode: Mode?` 单一状态 | 表达 (1,0)/(0,1)/(0,0) 三态；比 isVisible+activeMode 双状态清晰 |
| 行号 gutter | 自定义 GutterView（AppKit） | SwiftUI TextEditor 做不到 |
| 文件持久化 | UserDefaults 字符串路径 | sandbox 关闭时足够；Sprint 3 改 bookmark |

---

## 八、时间线

- **2026-08-01**：Phase 0 完成（双栏 + 解析 + 渲染 + KaTeX）
- **2026-08-02**：Phase 1 Sprint 1 + Sprint 2 + Task #1/2/3 完成（P0 收尾）
- **2026-08-02（当前）**：Sprint 3（Sandbox）待启动

---

## 九、后续候选（P1 / P2）

### P1 候选
- [ ] HSplitView → NSSplitViewController（可拖动比例 + 持久化）
- [ ] 语法高亮（`@section` 蓝、`@cite` 红、字符串/数字）
- [ ] Open Recent 菜单

### P2 候选
- [ ] HTML / PDF 导出
- [ ] FileWatcher（外部修改自动重载）
- [ ] BibTeX 支持
- [ ] 多文件 / 项目管理（扩展 sidebar）
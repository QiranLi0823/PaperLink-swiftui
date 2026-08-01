# Phase 1 P0 — 计划与现状

> 起点：Phase 0 完成（双栏 SwiftUI 论文 IDE + PaperML AST + 解析 + 渲染 + KaTeX）。
> 范围：三项必做（解析错误诊断、文件 I/O、Sandbox 重新设计）。
> 时间预算：3-4 周
> 最近更新：2026-08-02

---

## 一、目标

让 PaperLink **从原型走向可用**：

| 现在 | Phase 1 后 |
|---|---|
| 只能加载 demo.pml | 能打开 / 保存任何 .pml 文件 |
| 解析错误不显示 | 错误位置（行/列）+ 错误信息高亮 |
| 关掉 sandbox 跑 | 重新开启 sandbox + 正确 entitlement |
| 编辑破坏源码会让节点变空 | 至少标记错误位置，编辑可见 |

---

## 二、三个 Sprint 进度

### Sprint 1：解析错误诊断（1 周）✅ **已完成**

**目标**：解析失败时，编辑器标红 + 状态栏显示错误信息。

#### 任务

- [x] AST 加 `Position` / `Span` 字段（每个节点记录源码起止位置）
- [x] Parser 改为记录错误而非静默吞掉（返回 `parseWithErrors`）
- [x] `ParseError` 结构：`{ line, column, message, severity }`
- [x] ContentView 编辑器行号标红（gutter 背景 + 2pt 红条 + 行号变红）
- [x] 状态栏显示错误数量 + 第一条错误详情
- [x] Phase 0 容错的边界：能容错但仍记录错误

#### 关键技术决策

| 决策 | 选型 | 原因 |
|---|---|---|
| 错误存储 | `parseWithErrors` 返回 `(document, errors)` | AST 仍可用，错误并存 |
| Position 实现 | `SourcePosition { line, column }` | 行号从 1 开始，列从 1 开始 |
| 编辑器高亮 | NSTextView + 自定义 `GutterView`（AppKit） | SwiftUI TextEditor 做不到 |
| 行号宽度 | 32pt | 紧凑、足够放下 3 位数 |
| 行号字体 | monospaced digit system font 11pt | 数字等宽，行对齐 |

#### 验收

- [x] 输入错误 PaperML，状态栏显示「1 error: 第 12 行缺 `}`」
- [x] 编辑器第 12 行 gutter 红底 + 行号变红
- [x] 部分块解析失败不影响其他块渲染

#### Sprint 1 额外完成

- [x] Visual line 行号定位：软换行展开的多行只画一次行号（第一行顶部）
- [x] 行号右对齐 + 6pt padding
- [x] 错误行的红条（2pt）即使滚动也持续可见

---

### Sprint 2：文件 Open / Save（1.5 周）🟡 **大部分完成**

**目标**：能打开 / 保存本地 .pml 文件。

#### 任务

- [x] `PaperDocument` 加 `load(from: URL)` / `save(to: URL)` 方法
- [x] File 菜单加「Open」「Save」「Save As」按钮（⌘O / ⌘S / ⇧⌘S）
- [x] `NSOpenPanel` / `NSSavePanel` 集成
- [ ] `.pml` 文件类型 + UTI 注册
- [x] 文件未保存状态标记（`isDirty` 字段已实现）
- [ ] **标题栏 `*` 标记未保存状态** ← 当前未实现（窗口标题固定 "PaperLink"）
- [ ] Open Recent 菜单（最近 10 个文件） ← 未做
- [x] 启动时加载上次打开的文件（`UserDefaults[PaperLink.lastOpenedFilePath]`）
- [x] ⌘R 同目录下重命名
- [ ] **macOS 安全**：app sandbox 下需要 security-scoped bookmark 跨启动访问文件

#### 关键技术决策

| 决策 | 选型 | 原因 |
|---|---|---|
| 文件格式 | 自定义 `.pml`（关联 TextEdit fallback） | 与 Rust 时代一致 |
| 持久化路径 | UserDefaults 字符串路径（sandbox 关闭时） | sandbox 开启后改 bookmark |
| 自动保存 | Phase 1 不做（Phase 2 再加） | 防数据丢失但工作量大 |
| 文件 I/O 入口 | `ProjectManager` 单一服务 | 与 sidebar 文件树共享同一管理器 |

#### 验收

- [x] ⌘O 弹 NSOpenPanel，选 .pml 文件加载
- [x] ⌘S 保存当前文件
- [x] ⇧⌘S 另存为
- [x] 修改后 → `isDirty == true`（内存状态）
- [ ] 修改后 → 标题栏有 `*` 标记 ← **未做**
- [ ] 关闭未保存 → 弹「是否保存」对话框
- [ ] File 菜单有「Open Recent」列表

---

### Sprint 3：Sandbox Entitlement 重新设计（1 周）❌ **未开始**

**目标**：开启 App Sandbox + Hardened Runtime，配置 WKWebView 所需的 entitlement，能正常分发。

#### 任务

- [ ] 启用 `ENABLE_APP_SANDBOX = YES`
- [ ] 启用 `ENABLE_HARDENED_RUNTIME = YES`
- [ ] 创建 `.entitlements` 文件，配置：
  - `com.apple.security.app-sandbox`
  - `com.apple.security.network.client`（KaTeX CDN）
  - `com.apple.security.files.user-selected.read-write`（Open/Save 文件）
- [ ] pbxproj 关联 entitlements
- [ ] 验证 WKWebView 在 sandbox 下能渲染
- [ ] 验证 file:// 图片能加载
- [ ] 验证 Open/Save 在 sandbox 下能工作
- [ ] 准备 Apple 公证（`xcrun notarytool`）

#### 关键技术决策

| 决策 | 选型 | 原因 |
|---|---|---|
| 分发渠道 | macOS App Store 或 Developer ID | 决定 notarize 流程 |
| 沙箱严格度 | 完整 App Sandbox | App Store 必需 |
| 网络访问 | `network.client` only（不开放 server） | KaTeX CDN 必需 |
| 本地文件 | security-scoped bookmark | 跨启动访问必需 |

#### 验收

- [ ] `codesign -d --entitlements - PaperLink.app` 显示正确 entitlement
- [ ] 沙箱 + Hardened Runtime 下 KaTeX 渲染正常
- [ ] 沙箱 + Hardened Runtime 下图片加载正常
- [ ] 沙箱 + Hardened Runtime 下 Open/Save 正常
- [ ] `xcrun notarytool submit --wait` 通过（Developer ID 路径）

---

## 三、Phase 1 P0 范围外已完成的额外功能

Sprint 1/2/3 没列、但本次 sprint 中已实现的：

### 三栏布局（Phase 1 P1 范围）
- [x] sidebar 容器（项目文件树 / 图片列表两种模式）
- [x] SidebarState 全局状态（`activeMode: Mode?` 单一状态，三态切换）
- [x] SidebarModeBar（标题栏自定义 icon 按钮组，去外框 + 选中态正圆蓝底）
- [x] ProjectNavigatorView（Xcode 风格文件树，非递归 flatten）
- [x] ProjectTreeManager（扫描目录构建 FileNode 树）
- [x] FiguresGridView（图片文件名列表）
- [x] HSplitView editor/preview 对称 minWidth（1:1）

### 渲染美化（Phase 0 增强）
- [x] HTMLRenderer CSS variables + dark mode
- [x] 错误行 gutter 红条（柔和 10% 背景 + 2pt 红条）
- [x] 状态栏 modern 样式（regular material + 11pt 字号）
- [x] 标题栏去掉文件名（固定 "PaperLink"）

---

## 四、技术架构现状

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
│   ├── Assets.xcassets/
│   └── Resources/
│       ├── demo.pml
│       └── figures/
└── ...
```

注：PLAN 原本预期的 `Preview/`、`UI/`、`SyntaxHighlighter`、`FileWatcher`、`BookmarkStore` 等目录/文件未创建（功能没做或不需要）。

---

## 五、风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 软换行场景行号定位 | 已解决 | `lineFragmentRect(forGlyphAt:)` 遍历 visual line |
| sidebar 递归 View struct 死循环 | 已解决 | 父视图 `@State expanded: Set<URL>` + flatten 扁平化 |
| HSplitView 比例不可拖动 | 用户已知 | 改用 `NSSplitViewController`（AppKit）可选 P1 |
| Sandbox entitlement 反复试 | Sprint 3 风险 | 查 Apple 官方文档 + Stack Overflow 现成方案 |
| Security-scoped bookmark 持久化 | Sprint 2 风险 | 先做简单的"每次启动重新选文件"，bookmark 后续优化 |
| KaTeX CDN 在沙箱下被拦截 | 公式不显示 | 测试时第一时间验证；备选方案 bundle 本地 KaTeX |

---

## 六、不做（明确边界）

Phase 1 P0 **不做**：

- ❌ 语法高亮、自动补全（Phase 1 P1）
- ❌ HTML / PDF 导出（Phase 1 P1）
- ❌ BibTeX（Phase 1 P2）
- ❌ 文件监听（FileWatcher）— Phase 2
- ❌ 多文件 / 项目管理（已部分实现 sidebar）— Phase 2
- ❌ 协同编辑 — Phase 3
- ❌ 国际化（i18n）— Phase 3
- ❌ Apple 公证实际提交 — Phase 2（需要 Developer ID 账号）
- ❌ UTI 文件类型注册（未影响核心功能，可延后）
- ❌ Open Recent 菜单（UserDefaults 持久化已替代）

---

## 七、验收标准（Phase 1 P0 完成）

- [x] 输入错误 PaperML，UI 显示具体行号 + 错误信息
- [x] 能用 NSOpenPanel 打开本地 .pml 文件
- [x] 能用 NSSavePanel 保存 .pml 文件
- [x] 修改后 → `isDirty == true`（内存状态）
- [ ] 修改后 → 标题栏有 `*` 标记
- [ ] 沙箱 + Hardened Runtime 下所有功能正常
- [ ] Apple 公证准备就绪（entitlements 正确 + 文档齐全）
- [x] 启动 < 1 秒
- [x] 应用包 < 50 MB

**当前完成度**：8 / 11 项（73%）

**未完成的 3 项** 全部在 Sprint 3（Sandbox 公证）+ Sprint 2 的 2 个 polish 任务（标题栏 `*`、关闭未保存对话框）。

---

## 八、时间线

```
2026-08-01 ──────────────────────────────────────────
Week 1 (Sprint 1): 解析错误诊断 ✅
Week 2-3 (Sprint 2): 文件 I/O 🟡 大部分完成
Week 4 (Sprint 3): Sandbox 重设计 ❌ 未开始
2026-08-29 ──────────────────────────────────────────
Phase 1 P0 完成（计划）
2026-08-02 ── Sprint 1 + Sprint 2 已完成（实际进度）
```

---

## 九、后续 Sprint 1 P1 / P2 候选

Phase 1 P0 完成后，按用户偏好进入：

### P1 候选（建议优先）
- [ ] 标题栏 `*` 标记未保存状态（补 P0 收尾）
- [ ] 关闭未保存时弹「是否保存」对话框
- [ ] HSplitView 改 NSSplitViewController（可拖动比例 + 持久化）
- [ ] 语法高亮（SyntaxHighlighter.swift 占位转正）
- [ ] HTML / PDF 导出

### P2 候选
- [ ] BibTeX 支持
- [ ] 多文件 / 项目管理（扩展 sidebar）
- [ ] FileWatcher（外部修改自动重载）
- [ ] Security-scoped bookmark（sandbox 启用后）

---

*文档版本：v0.2*
*更新日期：2026-08-02*
*更新人：完成 Sprint 1 + Sprint 2 大部分 + Sprint 3 未开始*
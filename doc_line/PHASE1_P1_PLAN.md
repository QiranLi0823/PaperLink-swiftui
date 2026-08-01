# Phase 1 P1 — 规划

> 阶段：Phase 1 P1
> 当前：v0.4 (P0 完成；进入 P1)
> 起草：2026-08-02

P0 已完成基础能力（解析错误诊断 + 文件 I/O + 标题栏 `*` + 关闭确认 + UTI 注册 + 图加载修复）。
P1 阶段目标：**让编辑器真正像一个能用的写作工具**——可调比例、语法可读、近期文件可达、最终能公网分发。

---

## 一、P1 总体目标

| 维度 | P0 状态 | P1 目标 |
|---|---|---|
| 窗口比例 | HSplitView 1:1 不可拖动 | 可拖动 + 持久化比例 |
| 代码可读性 | 纯文本单色 | 语法高亮（关键字 / 字段 / 字符串 / 数字） |
| 文件访问 | 仅 Open… 菜单 | Open Recent（最近 10 个） + Dock 右键 |
| 安全/分发 | Sandbox OFF | Sandbox ON + 公证脚本 |
| 编辑体验 | 键盘⌘O/S/⇧S/⌘R | ⌘F 查找 / ⌘G 替换 / ⌘+ 放大 |

---

## 二、Sprint 划分

### Sprint 4：可拖动 split + 比例持久化 ⭐️

**目标**：HSplitView → NSSplitViewController，可拖动 splitter，比例写到 UserDefaults。

| # | 子步骤 | 涉及文件 | 估时 |
|---|---|---|---|
| 4.1 | 新建 `EditorSplitViewController: NSSplitViewController`，两个 NSSplitViewItem（editor / preview） | `Editor/EditorSplitViewController.swift`（新） | 30m |
| 4.2 | 加 NSViewController 包装 LineNumberedEditor 和 HTMLPreview | `Editor/EditorPaneVC.swift`（新）、`Editor/PreviewPaneVC.swift`（新） | 30m |
| 4.3 | ContentView 用 `NSViewControllerRepresentable` 包装 | `ContentView.swift` | 20m |
| 4.4 | 实现 `splitView(_:canCollapseSidebar:) → false`（不允许折叠） | `EditorSplitViewController.swift` | 5m |
| 4.5 | 实现 `splitView(_:constrainMinCoordinate:ofSubviewAt:)` — editor/preview 各 ≥ 380 | 同上 | 10m |
| 4.6 | UserDefaults 持久化 `splitFraction`，启动时 `setPosition` | `EditorSplitViewController.swift` + `ContentView.swift` | 20m |
| 4.7 | 拖动时实时写 UserDefaults（debounce 200ms） | 同上 | 10m |
| 4.8 | 验证：拖动 splitter → 关闭 app → 重启 → 比例保持 | 手动测试 | 5m |

**验证**：拖动 splitter → 关闭 → 重启 → 比例保持 ✅

---

### Sprint 5：语法高亮 ⭐️

**目标**：把 LineNumberedEditor 升级到语法高亮版本，关键字 / 字段 / 字符串 / 数字四类。

| # | 子步骤 | 涉及文件 | 估时 |
|---|---|---|---|
| 5.1 | 设计高亮规则：关键字（`@section`/`@figure`/...）、字段名（`@title`/`@path`/...）、字符串、数字 | `Editor/SyntaxRules.swift`（新） | 20m |
| 5.2 | 用 NSTextStorage + NSTextLayoutManager（macOS 15+）替换裸 NSTextView | `Editor/LineNumberedEditor.swift` | 60m |
| 5.3 | 实现 SyntaxHighlighter：增量扫描（NSRegularExpression） + 应用 attributes（颜色 + 字体 weight） | `Editor/SyntaxHighlighter.swift`（新） | 60m |
| 5.4 | 颜色方案：keyword = accentColor, field = 系统绿, string = 系统橙, number = 系统紫 | `Editor/Theme.swift`（新） | 10m |
| 5.5 | 编辑时增量更新（监听 NSTextStorageDidProcessEditing） | `Editor/LineNumberedEditor.swift` | 30m |
| 5.6 | 大文件性能测试：1000+ 行延迟 < 50ms | 手动测试 | 10m |

**验证**：输入 `@section { ... }` → 关键字蓝色 / 字段绿色 / 字符串橙色 ✅

---

### Sprint 6：Open Recent + 增强文件访问

**目标**：菜单 Open Recent 显示最近 10 个文件，UserDefaults 改 bookmark。

| # | 子步骤 | 涉及文件 | 估时 |
|---|---|---|---|
| 6.1 | 重构：lastOpenedFilePath 改 security-scoped bookmark | `Models/PaperDocument.swift` | 30m |
| 6.2 | NSOpenPanel 创建的文件 → 立即存 bookmark | `Models/PaperDocument.swift` | 15m |
| 6.3 | 启动时：解析 bookmark → 如失效 fallback bundle demo | `Models/PaperDocument.swift` | 15m |
| 6.4 | File 菜单加 Open Recent 子菜单（动态生成 NSDocumentController-style） | `PaperLinkApp.swift` | 30m |
| 6.5 | Open Recent 点击 → document.open(bookmark-resolved url) | `PaperLinkApp.swift` | 10m |
| 6.6 | Open Recent 提供 "Clear Menu" | `PaperLinkApp.swift` | 5m |

**验证**：⌘O 打开 3 个文件 → File 菜单 Open Recent 显示 → 重启 → 仍能打开 ✅

---

### Sprint 7：Sandbox + 公证 ⭐️

**目标**：开 sandbox + hardened runtime，能 `notarytool` 公证通过。

| # | 子步骤 | 涉及文件 | 估时 |
|---|---|---|---|
| 7.1 | 创建 entitlements 文件：`com.apple.security.app-sandbox` + `com.apple.security.files.user-selected.read-write` + `com.apple.security.network.client` | `PaperLink/PaperLink/PaperLink.entitlements`（新） | 10m |
| 7.2 | pbxproj：Debug/Release 都设 `CODE_SIGN_ENTITLEMENTS = PaperLink/PaperLink.entitlements` | `project.pbxproj` | 5m |
| 7.3 | pbxproj：`ENABLE_APP_SANDBOX = YES` + `ENABLE_HARDENED_RUNTIME = YES` | `project.pbxproj` | 5m |
| 7.4 | 把 UserDefaults 路径改成 bookmark（已在 Sprint 6） | 见 Sprint 6 | — |
| 7.5 | WKWebView helper 进程：sandbox 下要 network client entitlement（已在 7.1） | — | — |
| 7.6 | 创建 `scripts/notarize.sh`：`xcrun notarytool submit` + `--wait` | `scripts/notarize.sh`（新） | 30m |
| 7.7 | 验证：archive → 上传 → 公证通过 → stapler → 安装运行 | 手动测试 | 30m |

**验证**：build → archive → 公证 → 安装 → 双击 .pml 仍能加载 ✅

---

### Sprint 8：编辑体验增强（可选）

**目标**：补全 macOS 编辑器标配。

| # | 子步骤 | 估时 |
|---|---|---|
| 8.1 | ⌘F 查找（NSFindPanel 集成） | 30m |
| 8.2 | ⌘G 替换 | 30m |
| 8.3 | ⌘+ / ⌘- 字号缩放 | 15m |
| 8.4 | 自动缩进（回车 → 复制上一行 indent） | 20m |
| 8.5 | 括号匹配高亮（`{` `}` `[` `]` `(` `)`） | 30m |

---

## 三、执行顺序（推荐）

```
Sprint 4 ──► Sprint 6 ──► Sprint 7 ──► Sprint 5 ──► Sprint 8
   │            │            │            │            │
   可拖动      Open Recent  Sandbox     语法高亮    编辑体验
   比例持久化   + bookmark   + 公证     增量渲染    标配补全
   (独立)      (Sprint 7    (依赖 6)   (独立)      (独立)
               前置)
```

理由：
- **Sprint 4 在前**：可拖动比例是日常基础，独立可做
- **Sprint 6 在 Sprint 7 前**：Sandbox 后强制需要 bookmark，否则 UserDefaults 路径访问被拒
- **Sprint 7 尽早做**：通过公证才能公网分发（TestFlight / dmg），且 sandbox 开/关需要回归测试
- **Sprint 5 后置**：语法高亮改动 LineNumberedEditor 内部，工作量大、独立；放后期减少对其他 sprint 的影响
- **Sprint 8 可选**：锦上添花，最后做

---

## 四、依赖与风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| NSSplitViewController 嵌入 SwiftUI | 拖动比例需要 NSViewControllerRepresentable | 参照 NSToolbar 嵌入实践 |
| Sandbox 下 WKWebView 加载 file:// | 图加载可能再次失败 | 7.1 加 file-access entitlement |
| 公证失败（signing identity / 团队） | 不能公网分发 | 复用现有 DEVELOPMENT_TEAM |
| SyntaxHighlighter 大文件性能 | 编辑卡顿 | 增量扫描 + dispatch background queue |
| Bookmark 失效（用户移动文件） | 启动 fallback bundle demo | 启动时 try/catch 兜底 |

---

## 五、里程碑

| 时间 | 节点 | 验证标准 |
|---|---|---|
| P1 Sprint 4 完成 | 可拖动比例 | 关闭重启比例保持 |
| P1 Sprint 6 完成 | Open Recent | 重启仍能列最近文件 |
| P1 Sprint 7 完成 | Sandbox + 公证 | notarize 成功 + 启动 + 加载文件 |
| P1 Sprint 5 完成 | 语法高亮 | 编辑流畅 + 颜色对 |
| P1 全部完成 | 可分发 | dmg + 公证 + 跨机器安装 |

---

## 六、不做（明确边界 P1）

- ❌ 多 tab 编辑
- ❌ LSP / 智能补全
- ❌ 协作 / Git 集成
- ❌ PDF / LaTeX / Docx 导出
- ❌ 跨平台（macOS only）

这些留给 P2 / P3。

---

## 七、当前状态（2026-08-02）

```
P0:  ✅ 完成（标题栏 * / 关闭确认 / UTI / 图加载）
P1:  📋 本文档规划
P2+:  ⏸️ 暂未规划
```
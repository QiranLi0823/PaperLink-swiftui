# Phase 1 P0 — 计划

> 起点：Phase 0 完成（双栏 SwiftUI 论文 IDE + PaperML AST + 解析 + 渲染 + KaTeX）。
> 范围：三项必做（解析错误诊断、文件 I/O、Sandbox 重新设计）。
> 时间预算：3-4 周
> 最近更新：2026-08-01

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

## 二、三个 Sprint

### Sprint 1：解析错误诊断（1 周）

**目标**：解析失败时，编辑器标红 + 状态栏显示错误信息。

#### 任务

- [ ] AST 加 `Position` / `Span` 字段（每个节点记录源码起止位置）
- [ ] Parser 改为记录错误而非静默吞掉（返回 `Result<PaperMLDocument, [ParseError]>`）
- [ ] `ParseError` 结构：`{ line, column, message, severity }`
- [ ] ContentView 编辑器行号标红（用 NSTextView 的 `layoutManager`）
- [ ] 状态栏显示错误数量 + 第一条错误详情
- [ ] Phase 0 容错的边界：能容错但仍记录错误

#### 关键技术决策

| 决策 | 选型 | 原因 |
|---|---|---|
| 错误存储 | `Result<Document, [ParseError]>` | AST 仍可用，错误并存 |
| Position 实现 | `SourcePosition { line, column }` | 行号从 1 开始，列从 1 开始 |
| 编辑器高亮 | NSTextView `layoutManager` 标红 | SwiftUI TextEditor 做不到 |

#### 验收

- [ ] 输入错误 PaperML，状态栏显示「1 error: 第 12 行缺 `}`」
- [ ] 编辑器第 12 行有红色下划线
- [ ] 部分块解析失败不影响其他块渲染

---

### Sprint 2：文件 Open / Save（1.5 周）

**目标**：能打开 / 保存本地 .pml 文件。

#### 任务

- [ ] `PaperDocument` 加 `load(from: URL)` / `save(to: URL)` 方法
- [ ] Toolbar 加「Open」「Save」「Save As」按钮
- [ ] `NSOpenPanel` / `NSSavePanel` 集成
- [ ] 支持 `.pml` 文件类型 + UTI 注册
- [ ] 文件未保存状态标记（标题栏 `*`）
- [ ] Open Recent 菜单（最近 10 个文件）
- [ ] **macOS 安全**：app sandbox 下需要 security-scoped bookmark 跨启动访问文件

#### 关键技术决策

| 决策 | 选型 | 原因 |
|---|---|---|
| 文件格式 | 自定义 `.pml`（关联 TextEdit fallback） | 与 Rust 时代一致 |
| Open Recent | UserDefaults + security-scoped bookmark | sandbox 必需 |
| 自动保存 | Phase 1 不做（Phase 2 再加） | 防数据丢失但工作量大 |

#### 验收

- [ ] ⌘O 弹 NSOpenPanel，选 .pml 文件加载
- [ ] ⌘S 保存当前文件
- [ ] ⇧⌘S 另存为
- [ ] 修改后未保存 → 标题栏有 `*`
- [ ] 关闭未保存 → 弹「是否保存」对话框
- [ ] File 菜单有「Open Recent」列表

---

### Sprint 3：Sandbox Entitlement 重新设计（1 周）

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

## 三、技术架构变化

```
PaperLink/
├── PaperLink/
│   ├── PaperLinkApp.swift              # @main + commands（File 菜单）
│   ├── ContentView.swift               # 双栏 + Toolbar + StatusBar
│   ├── Editor/
│   │   ├── EditorView.swift            # NSTextView 包装 + 错误标红
│   │   └── SyntaxHighlighter.swift     # Phase 1 后做，先占位
│   ├── Preview/
│   │   ├── PreviewView.swift
│   │   └── KaTeXInjector.swift
│   ├── PaperCore/
│   │   ├── PaperMLAST.swift            # 加 Position 字段
│   │   ├── PaperMLParser.swift         # 返 Result<Doc, [Error]>
│   │   ├── ParseError.swift            # 新文件
│   │   └── HTMLRenderer.swift
│   ├── FileSystem/
│   │   ├── ProjectManager.swift        # 新文件：Open / Save
│   │   ├── FileWatcher.swift           # Phase 1 后做，先占位
│   │   └── BookmarkStore.swift         # 新文件：security-scoped bookmark
│   ├── UI/
│   │   ├── Toolbar.swift               # Open / Save 按钮
│   │   └── StatusBar.swift             # 错误信息显示
│   ├── Models/
│   │   └── PaperDocument.swift         # + URL? + isDirty
│   └── PaperLink.entitlements          # 新文件
└── ...
```

---

## 四、风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| NSTextView 错误高亮复杂 | Sprint 1 延期 | 简化：只标红行背景（不上 underlines） |
| Sandbox entitlement 反复试 | Sprint 3 延期 | 查 Apple 官方文档 + Stack Overflow 现成方案 |
| Security-scoped bookmark 持久化 | Sprint 2 延期 | 先做简单的"每次启动重新选文件"，bookmark 后续优化 |
| KaTeX CDN 在沙箱下被拦截 | 公式不显示 | 测试时第一时间验证；备选方案 bundle 本地 KaTeX |

---

## 五、不做（明确边界）

Phase 1 P0 **不做**：

- ❌ 语法高亮、自动补全（Phase 1 P1）
- ❌ HTML / PDF 导出（Phase 1 P1）
- ❌ BibTeX（Phase 1 P2）
- ❌ 文件监听（FileWatcher）— Phase 2
- ❌ 多文件 / 项目管理 — Phase 2
- ❌ 协同编辑 — Phase 3
- ❌ 国际化（i18n）— Phase 3
- ❌ Apple 公证实际提交 — Phase 2（需要 Developer ID 账号）

---

## 六、验收标准（Phase 1 P0 完成）

- [ ] 输入错误 PaperML，UI 显示具体行号 + 错误信息
- [ ] 能用 NSOpenPanel 打开本地 .pml 文件
- [ ] 能用 NSSavePanel 保存 .pml 文件
- [ ] 修改后未保存 → 标题栏有 `*` 标记
- [ ] 沙箱 + Hardened Runtime 下所有功能正常
- [ ] Apple 公证准备就绪（entitlements 正确 + 文档齐全）
- [ ] 启动 < 1 秒（Phase 0 标准保持）
- [ ] 应用包 < 50 MB

---

## 七、时间线

```
2026-08-01 ──────────────────────────────────────────
Week 1 (Sprint 1): 解析错误诊断
Week 2-3 (Sprint 2): 文件 I/O
Week 4 (Sprint 3): Sandbox 重设计
2026-08-29 ──────────────────────────────────────────
Phase 1 P0 完成
```

---

*文档版本：v0.1*
*创建日期：2026-08-01*

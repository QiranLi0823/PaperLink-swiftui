# 块级元素

`@figure` / `@table` / `@equation` 是章节内部的块级结构，必须出现在 `@section` 或 `@subsection` 内部。

## @figure

```
@figure{
  @path    = "figures/<file>.png"   ← 相对路径，从 .pml 同目录解析
  @caption = "<caption text>"
  @label   = "fig:<key>"             ← 可选，用于 @ref 引用
}
```

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@path` | string | ✓ | 图片相对路径（`.pml` 同目录） |
| `@caption` | string | | 图片说明 |
| `@label` | string | | 唯一 label，`@ref{fig:<key>}` 引用 |

### 图片路径解析规则

按顺序查找：

1. **用户文档**：`/path/to/foo.pml` 同目录 → `<file>.png`
2. **Bundle fallback**：`Bundle.main/figures/<file>.png`（demo 用）
3. 都找不到 → 显示 `[image not found: <path>]` 占位框

支持格式：`png` / `jpg` / `jpeg` / `gif` / `webp` / `svg`。

### 示例

```pml
@section Method
@subsection Framework Overview
As shown in @ref{fig:framework}, our model consists of three parts.

@figure{
  @path = "figures/framework.png"
  @caption = "Overview of the proposed framework."
  @label = "fig:framework"
}
```

## @table

```
@table{
  @caption = "<caption text>"
  @label   = "tab:<key>"                    ← 可选
  @columns = ["col1", "col2", ...]
  @rows    = [
    ["r1c1", "r1c2", ...],
    ["r2c1", "r2c2", ...]
  ]
}
```

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@caption` | string | | 表格说明 |
| `@label` | string | | 唯一 label |
| `@columns` | string[] | ✓ | 表头，每列一个 |
| `@rows` | string[][] | ✓ | 数据行，外层每个元素是一行 |

### 约束

- `@columns` 和 `@rows` 的每行长度必须一致
- `@rows` 至少 1 行
- 字符串里可以用 `"` 转义为 `\"`，但**不支持跨行字符串**

### 示例

```pml
@table{
  @caption = "Comparison with state-of-the-art methods on ETH-UCY (ADE/FDE in meters)"
  @label = "tab:eth_results"
  @columns = ["Method", "ETH", "Hotel", "Univ", "Avg"]
  @rows = [
    ["Social-GAN", "0.81/1.52", "0.72/1.61", "0.60/1.26", "0.58/1.18"],
    ["Trajectron++", "0.67/1.18", "0.43/0.86", "0.56/1.17", "0.46/0.91"],
    ["Ours", "0.40/0.68", "0.12/0.19", "0.22/0.40", "0.20/0.35"]
  ]
}
```

渲染为带圆角边框 + 表头斑马底色的 HTML `<table>`，引用用 `@ref{tab:eth_results}`。

## @equation

块级公式（display math），独立成块渲染。

### 写法 1：brace 块（推荐）

```
@equation{
  @content = "<LaTeX source>"
  @label   = "eq:<key>"       ← 可选
}
```

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@content` | string | ✓ | LaTeX 数学源码（不带 `$$`） |
| `@label` | string | | 唯一 label，`@ref{eq:<key>}` 引用 |

### 写法 2：行内 + 子字段（兼容老格式）

```
@equation
  @content = "..."
  @label = "..."
```

不推荐，brace 写法更易读、跟 `@figure` / `@table` 一致。

### 示例

```pml
@subsection Loss Function
We minimize the displacement error defined in @ref{eq:loss}:

@equation{
  @content = "\\mathcal{L} = \\frac{1}{N} \\sum_{i=1}^{N} \\|\\hat{y}_i - y_i\\|_2^2"
  @label = "eq:loss"
}
```

### KaTeX 限制

- 渲染走 KaTeX CDN（[katex.org](https://katex.org/)）
- 支持的宏：`\frac \sum \int \sqrt \hat \mathcal \mathbb ...`
- **不支持**：`\label` `\ref`（PaperML 自己处理，不用 LaTeX 的）
- **不支持**：`\begin{...} \end{...}`（align / cases 等环境不能直接用）

## 块与段落的关系

brace 块（`@figure` / `@table` / `@equation`）**闭合 `}` 后紧跟的裸文本行**会作为独立 paragraph 渲染。这是合法的，常见用法是「表格后面的说明文字」：

```pml
@table{
  @caption = "..."
  @columns = [...]
  @rows = [...]
}

As shown in @ref{tab:results}, our method achieves the best performance.
```

`As shown in ...` 这一段会被识别成 paragraph[9]（如果它前面有 9 个其它 paragraph）。

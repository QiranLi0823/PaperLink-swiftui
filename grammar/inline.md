# 行内元素

行内元素只能出现在段落文本里（`@section` 后面的普通文字行、`@abstract` 内部、brace 闭合后跟的裸文本）。

## 普通文本

任意字符序列，**除了**以下起始 token：
- `@` 开头 → 进入字段标识符（`@cite` / `@ref` / 已知字段名）
- `$` 开头 → 进入行内数学（见下）
- `//` → 注释到行尾（被解析器忽略）
- `\n` / 空行 → 段落结束

### 转义

| 写法 | 含义 |
|---|:--|
| `\{` | 字面 `{`（在 brace 块内必要） |
| `\}` | 字面 `}` |
| `\\` | 字面 `\` |
| `\$` | 字面 `$` |
| `\@` | 字面 `@`（段落里 `@` 通常是字段起始，但 `\@` 是字面字符） |

## @cite

行内引用文献，渲染为蓝色 `[n]` 角标 + key 名。

```
@cite{<key>}
```

| 部分 | 说明 |
|---|---|
| `<key>` | 文献 key（任意标识符，无注册表） |

### 示例

```pml
Recent advances in deep learning have enabled significant progress
@cite{gupta2018social} @cite{alahi2016social}.
```

渲染：

> Recent advances in deep learning have enabled significant progress <sup>[1]</sup>`gupta2018social` <sup>[2]</sup>`alahi2016social`.

同一段落内的多个 `@cite` 共享 `[n]` 编号（每段从 `[1]` 重置），key 在 `[n]` 后作为灰色等宽显示。

### 限制

- 没有 `.bib` 文件——key 只是字符串，不做解析
- 不支持多个 key 一次引用：`@cite{a, b, c}` ❌（要写三次 `@cite{a} @cite{b} @cite{c}`）

## @ref

行内交叉引用，渲染为上标编号。

```
@ref{<label>}
```

`<label>` 必须是 `@figure` / `@table` / `@equation` 中**已定义**的 `@label` 值。

### 解析规则

- 第一次出现 → 显示新编号 `<sup>1</sup>`
- 之后出现 → 复用第一次的编号（不会重复编号）

### 示例

```pml
As shown in @ref{fig:framework}, our model has three components.
The loss function @ref{eq:loss} is minimized end-to-end.
Results in @ref{tab:eth_results} demonstrate state-of-the-art performance.
```

渲染：

> As shown in <sup>1</sup>, our model has three components. The loss function <sup>2</sup> is minimized end-to-end. Results in <sup>3</sup> demonstrate state-of-the-art performance.

### 错误处理

引用了未定义的 label → 解析器报告 `ParseError`，但**不会崩溃**——渲染时会显示为普通文本 `@ref{<label>}`（让你知道哪儿没定义）。

## 行内数学

KaTeX 渲染，支持 4 种 delimiters（参考 KaTeX auto-render 配置）：

| 写法 | 渲染为 |
|---|---|
| `$...$` | 行内 inline math |
| `$$...$$` | block display math |
| `\[...\]` | block display math |
| `\(...\)` | 行内 inline math |

### 示例

```pml
The loss function $L = \frac{1}{N} \sum \| \hat{y}_i - y_i \|^2$ is minimized
end-to-end. The optimization is equivalent to solving

$$ \min_\theta \mathbb{E}_{(x, y) \sim \mathcal{D}} \left[ \mathcal{L}(f_\theta(x), y) \right] $$

which converges under standard assumptions.
```

### 限制

- `$` 在 PaperML 文本里必须配对出现，单 `$` 会导致解析错误
- `\(` 和 `\[` 在 brace 块内需要 `\\(` / `\\[` 转义（避免被当 brace 配对吃掉）

## 段落与块级的边界

行内元素不能出现在 brace 块字段值外面。比如：

```pml
@figure{
  @caption = "Overview. Note $E = mc^2$ here."   ← ✓ $...$ 在 @caption 值里合法
  @path = "figures/x.png"
}
```

但：

```pml
@figure
  @caption = "..."
  $E = mc^2$   ← ✗ 不在 brace 内，是 @figure 块外的裸文本，被当成新 paragraph
```

brace 块必须用 `}` 显式闭合。

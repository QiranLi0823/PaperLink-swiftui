# PaperML 语法参考

PaperML 是 PaperLink 编辑器的源文件格式（`.pml`）。这份目录是语法的**权威参考**——每个 block 的字段、嵌套规则、示例、quirks 都在这里。

如果 README.md 是「产品手册」，这里就是「语言手册」。

## 目录

- [顶层元数据](./top-level.md) — `@title` / `@author` / `@footnote` / `@abstract`
- [章节标题](./top-level.md#section--subsection) — `@section` / `@subsection`
- [块级元素](./blocks.md) — `@figure` / `@table` / `@equation`
- [行内元素](./inline.md) — 普通文本 / `@cite` / `@ref` / `$...$` 行内数学

## 词法约定

- **字段前缀 `@`**：所有结构标识符都带 `@`，包括 `@title` 块内 `title` 字段也写成 `@title`
- **brace 块**：复杂结构用 `{ ... }` 包起来，内部是 `@key = value` 形式的字段
- **裸文本行**：紧跟 brace 块、不是 `@` 开头的一行或多行连续非空文本 = 一个 paragraph
- **空行 / `//` 注释**：渲染时被忽略（不占渲染空间），用于段落分隔
- **LaTeX 转义**：`\{` `\}` 在 brace 内是字面字符，不参与配对

## 一份最小可工作的 PaperML

```pml
@title{
  @title = "Hello PaperLink"
  @author{
    @name = "Anonymous"
  }
}

@abstract{
  @keywords = ["demo", "PaperML"]
  This is a minimal PaperML document.
}

@section Introduction
The first section starts here @cite{vaswani2017attention}.
```

## 设计原则

- **机器可读优先**：语法是 AST-driven 的（`PaperMLParser.swift`），不是 markdown 风格
- **字段而非位置**：`@caption = "..."` 而不是位置参数，重排不影响解析
- **显式 nesting**：`@title{ @author{ ... } }` 嵌套结构清晰，跨段落传递上下文不靠缩进
- **LaTeX 数学子集**：`$...$` / `$$...$$` / `\[...\]` / `\(`...`\)`，KaTeX 渲染

## 与其它格式的关系

| 格式 | 区别 |
|---|---|
| Markdown | 没有 AST，所有结构靠 `#` 标题 / 空行分隔，不机器可读 |
| LaTeX | 语法更复杂（preamble / packages），PaperML 只想表达论文结构不表达排版细节 |
| HTML | 过度表达，把样式和数据耦合 |

PaperML 的目标是「论文内容的结构化表示」——**作者只关心语义，不关心 CSS**。

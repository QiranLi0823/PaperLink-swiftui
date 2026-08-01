# 顶层元数据 & 章节标题

所有顶层块都出现在文档根，不嵌套在 `@section` 内。

## @title

论文标题块。**必须是文档第一个块**。

```
@title{
  @title    = "<paper title>"
  @author   { ... }    # 1..N 个
  @footnote { ... }    # 0..N 个
}
```

### 字段

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@title` | string | ✓ | 论文主标题 |
| `@author` | block | ✓ | 至少 1 个作者 |
| `@footnote` | block | | 可选脚注（equal contribution / corresponding 等标记说明） |

### @author 子块

```
@author{
  @name         = "<full name>"
  @affiliation  = "<institution>"
  @email        = "<email>"
  @orcid        = "<0000-0000-0000-0000>"
  @note         = "<footnote label, e.g. equal_contribution>"
  @corresponding = "true" | "false"
}
```

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@name` | string | ✓ | 作者全名 |
| `@affiliation` | string | | 单位 |
| `@email` | string | | 邮箱 |
| `@orcid` | string | | ORCID 标识符 |
| `@note` | string | | 脚注 label（对应 `@footnote{ @label = "..." }`） |
| `@corresponding` | bool | | 是否通讯作者，true 时显示 `*` 角标 |

### @footnote 子块

```
@footnote{
  @marker = "†" | "*" | "<char>"
  @label  = "<key>"            # 唯一 key，跟 @author.@note 对应
  <free text>                  # 脚注正文
}
```

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@marker` | string | ✓ | 渲染的脚注符号（`†` `*` `‡` 等 Unicode） |
| `@label` | string | | 唯一 key（被 `@author.@note` 引用） |
| 裸文本 | | ✓ | 脚注正文 |

### 完整示例

```pml
@title{
  @title = "A Novel Trajectory Prediction Framework Based on Transformer"

  @author{
    @name = "Author One"
    @affiliation = "Tsinghua University"
    @email = "author1@tsinghua.edu.cn"
    @note = "equal_contribution"
  }

  @author{
    @name = "Author Three"
    @corresponding = "true"
    @email = "author3@example.com"
  }

  @footnote{
    @marker = "†"
    @label = "equal_contribution"
    These authors contributed equally to this work.
  }
}
```

## @abstract

论文摘要块，紧跟 `@title`。

```
@abstract{
  @keywords = ["k1", "k2", ...]
  <paragraph 1>
  <paragraph 2>
  ...
}
```

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `@keywords` | string[] | | 关键词数组 |
| 裸文本 | | ✓ | 一段或多段摘要正文（空行分段） |

### 示例

```pml
@abstract{
  @keywords = ["Trajectory Prediction", "Transformer", "Autonomous Driving"]
  Trajectory prediction is a critical component for autonomous driving systems.
  We propose a novel framework based on the Transformer architecture.
}
```

## @section / @subsection

章节标题，**必须出现在 `@abstract` 之后**。

```
@section    <title text>      ← 一级（渲染为 h2）
@subsection <title text>      ← 二级（渲染为 h3，缩进嵌入最近 @section）
```

**注意**：标题文本紧跟 `@section` / `@subsection` 关键字在同一行，**不需要 brace**。

### 嵌套规则

- `@subsection` 自动嵌套进**最近的** `@section` 的 `children`
- 一个 `@section` 可以有多个 `@subsection`
- `@subsection` 下不能直接放 `@section`（这是论文层级约定，不是语法限制——但建议遵守）

### 章节内部可放

- 普通 paragraph 段落
- `@figure` / `@table` / `@equation` 块（参见 [blocks.md](./blocks.md)）
- `@cite` / `@ref` / 行内数学（参见 [inline.md](./inline.md)）
- 嵌套 `@subsection`

### 示例

```pml
@section Introduction
This section introduces the problem.

@section Related Work
@subsection Trajectory Prediction
Existing methods fall into two categories...

@subsection Autonomous Driving
Recent work leverages attention mechanisms...

@section Method
Our framework consists of three components.
```

## 完整顺序

一个合规的 `.pml` 文档顶层块应按这个顺序：

```
@title { ... }
@abstract { ... }
@section A
  text + @figure + @table + @equation
  @subsection A.1
    text + ...
  @subsection A.2
    ...
@section B
  ...
```

顺序错了解析器**不会报错**（`PaperMLParser` 容错），但人类阅读会觉得奇怪。

//! AST (Abstract Syntax Tree) definitions for PaperML
//!
//! The AST represents the structure of a scientific paper in a
//! format-independent way, similar to HTML DOM.

use serde::{Deserialize, Serialize};

/// Root document node
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Document {
    /// Document metadata (title, authors, footnotes, etc.)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub meta: Option<Meta>,
    /// Document content blocks
    pub content: Vec<Block>,
}

/// Document metadata (inside @title{...})
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Meta {
    /// Paper title
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Authors
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub authors: Vec<Author>,
    /// Footnotes (equal contribution, corresponding author, etc.)
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub footnotes: Vec<Footnote>,
    /// Keywords (inside @abstract{...})
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub keywords: Vec<String>,
    /// Abstract text
    #[serde(skip_serializing_if = "Option::is_none")]
    pub abstract_text: Option<String>,
}

/// Author information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Author {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub affiliation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub orcid: Option<String>,
    /// e.g. "equal_contribution"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// true if this is a corresponding author
    #[serde(skip_serializing_if = "Option::is_none")]
    pub corresponding: Option<bool>,
}

impl Author {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            affiliation: None,
            email: None,
            orcid: None,
            note: None,
            corresponding: None,
        }
    }
}

/// Footnote (e.g. equal contribution, corresponding author)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Footnote {
    /// Display marker, e.g. "†" or "*"
    pub marker: String,
    /// Label to match with author.note or author.corresponding
    pub label: String,
    /// Footnote text body
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
}

impl Footnote {
    pub fn new(marker: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            marker: marker.into(),
            label: label.into(),
            body: None,
        }
    }
}

/// Block-level elements
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Block {
    Section(Section),
    Paragraph(Paragraph),
    Figure(Figure),
    Table(Table),
    Equation(Equation),
}

/// Section (chapter) node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Section {
    /// Section level: 1 = section, 2 = subsection, 3 = subsubsection
    pub level: u8,
    /// Section title
    pub title: String,
    /// Optional label for cross-references
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    /// Child blocks within this section
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub children: Vec<Block>,
}

/// Paragraph node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paragraph {
    /// Inline content within the paragraph
    pub content: Vec<Inline>,
}

/// Figure node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Figure {
    /// Image path
    pub path: String,
    /// Figure caption
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
    /// Label for cross-references
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

/// Table node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Table {
    /// Table caption
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
    /// Label for cross-references
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    /// Column headers
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub columns: Vec<String>,
    /// Table rows (each row is a vector of cell values)
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub rows: Vec<Vec<String>>,
}

/// Equation node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Equation {
    /// LaTeX math content
    pub content: String,
    /// Label for cross-references
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

/// Inline elements within paragraphs
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Inline {
    /// Plain text
    Text { value: String },
    /// Citation reference
    Citation { key: String },
    /// Cross-reference to figure/table/equation
    Reference { target: String },
    /// Inline math
    Math { content: String },
    /// Bold text
    Bold { content: Vec<Inline> },
    /// Italic text
    Italic { content: Vec<Inline> },
}

// Constructor impls

impl Document {
    pub fn new() -> Self {
        Self::default()
    }
}

impl Section {
    pub fn new(level: u8, title: impl Into<String>) -> Self {
        Self {
            level,
            title: title.into(),
            label: None,
            children: Vec::new(),
        }
    }
}

impl Paragraph {
    pub fn new(content: Vec<Inline>) -> Self {
        Self { content }
    }

    pub fn from_text(text: impl Into<String>) -> Self {
        Self {
            content: vec![Inline::Text { value: text.into() }],
        }
    }
}

impl Figure {
    pub fn new(path: impl Into<String>) -> Self {
        Self {
            path: path.into(),
            caption: None,
            label: None,
        }
    }
}

impl Table {
    pub fn new() -> Self {
        Self {
            caption: None,
            label: None,
            columns: Vec::new(),
            rows: Vec::new(),
        }
    }
}

impl Default for Table {
    fn default() -> Self {
        Self::new()
    }
}

impl Equation {
    pub fn new(content: impl Into<String>) -> Self {
        Self {
            content: content.into(),
            label: None,
        }
    }
}

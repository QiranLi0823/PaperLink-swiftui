//! PaperML Parser
//!
//! Parses PaperML text into an AST using pest.

use pest::Parser;
use pest::iterators::Pair;
use pest_derive::Parser;
use thiserror::Error;

use crate::ast::*;

// The pest grammar, loaded from grammar.pest
#[derive(Parser)]
#[grammar = "grammar.pest"]
struct PaperMLParser;

#[derive(Error, Debug)]
pub enum ParseError {
    #[error("Parse error: {0}")]
    PestError(String),
    #[error("Invalid syntax: {0}")]
    InvalidSyntax(String),
}

/// Parse PaperML text into a Document AST
pub fn parse(input: &str) -> Result<Document, ParseError> {
    let pairs = PaperMLParser::parse(Rule::document, input)
        .map_err(|e| ParseError::PestError(e.to_string()))?;
    let mut doc = Document::new();

    for pair in pairs {
        match pair.as_rule() {
            Rule::document => {
                for inner in pair.into_inner() {
                    match inner.as_rule() {
                        Rule::title_block => {
                            doc.meta = Some(parse_title(inner)?);
                        }
                        Rule::abstract_block => {
                            let (text, keywords) = parse_abstract(inner)?;
                            doc.meta = Some(doc.meta.take().unwrap_or_default());
                            if let Some(kw) = keywords {
                                if let Some(ref mut m) = doc.meta {
                                    m.keywords = kw;
                                }
                            }
                            if let Some(ref mut m) = doc.meta {
                                m.abstract_text = Some(text);
                            }
                        }
                        Rule::section => {
                            doc.content.push(Block::Section(parse_section(inner, 1)?));
                        }
                        Rule::subsection => {
                            doc.content.push(Block::Section(parse_section(inner, 2)?));
                        }
                        Rule::subsubsection => {
                            doc.content.push(Block::Section(parse_section(inner, 3)?));
                        }
                        Rule::figure => {
                            doc.content.push(Block::Figure(parse_figure(inner)?));
                        }
                        Rule::table => {
                            doc.content.push(Block::Table(parse_table(inner)?));
                        }
                        Rule::equation => {
                            doc.content.push(Block::Equation(parse_equation(inner)?));
                        }
                        Rule::paragraph => {
                            doc.content.push(Block::Paragraph(parse_paragraph(inner)?));
                        }
                        Rule::NEWLINE | Rule::COMMENT => {}
                        Rule::EOI => {}
                        _ => {}
                    }
                }
            }
            Rule::EOI => {}
            _ => {}
        }
    }

    Ok(doc)
}

// ─── Title block ───────────────────────────────────────────────────────────────

fn parse_title(pair: Pair<Rule>) -> Result<Meta, ParseError> {
    let mut meta = Meta::default();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::title_attr => {
                // title = "..."
                meta.title = Some(extract_quoted_string(inner)?);
            }
            Rule::author_block => {
                meta.authors.push(parse_author(inner)?);
            }
            Rule::footnote_block => {
                meta.footnotes.push(parse_footnote(inner)?);
            }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    Ok(meta)
}

// ─── Author ──────────────────────────────────────────────────────────────────

fn parse_author(pair: Pair<Rule>) -> Result<Author, ParseError> {
    let mut author = Author::new("");

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::author_inner => {
                for attr in inner.into_inner() {
                    match attr.as_rule() {
                        Rule::author_name => { author.name = extract_quoted_string(attr)?; }
                        Rule::author_affiliation => { author.affiliation = Some(extract_quoted_string(attr)?); }
                        Rule::author_email => { author.email = Some(extract_quoted_string(attr)?); }
                        Rule::author_orcid => { author.orcid = Some(extract_quoted_string(attr)?); }
                        Rule::author_note => { author.note = Some(extract_quoted_string(attr)?); }
                        Rule::author_corresponding => {
                            let v = extract_quoted_string(attr)?;
                            author.corresponding = Some(v == "true");
                        }
                        Rule::NEWLINE => {}
                        _ => {}
                    }
                }
            }
            Rule::author_name => { author.name = extract_quoted_string(inner)?; }
            Rule::author_affiliation => { author.affiliation = Some(extract_quoted_string(inner)?); }
            Rule::author_email => { author.email = Some(extract_quoted_string(inner)?); }
            Rule::author_orcid => { author.orcid = Some(extract_quoted_string(inner)?); }
            Rule::author_note => { author.note = Some(extract_quoted_string(inner)?); }
            Rule::author_corresponding => {
                let v = extract_quoted_string(inner)?;
                author.corresponding = Some(v == "true");
            }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    Ok(author)
}

// ─── Footnote ────────────────────────────────────────────────────────────────

fn parse_footnote(pair: Pair<Rule>) -> Result<Footnote, ParseError> {
    let mut footnote = Footnote::new("", "");
    let mut body_parts: Vec<&str> = Vec::new();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::footnote_inner => {
                for attr in inner.into_inner() {
                    match attr.as_rule() {
                        Rule::footnote_marker => { footnote.marker = extract_quoted_string(attr)?; }
                        Rule::footnote_label => { footnote.label = extract_quoted_string(attr)?; }
                        Rule::footnote_body => {
                            let s = attr.as_str().trim();
                            if !s.is_empty() { body_parts.push(s); }
                        }
                        Rule::NEWLINE => {}
                        _ => {}
                    }
                }
            }
            Rule::footnote_marker => { footnote.marker = extract_quoted_string(inner)?; }
            Rule::footnote_label => { footnote.label = extract_quoted_string(inner)?; }
            Rule::footnote_body => {
                let s = inner.as_str().trim();
                if !s.is_empty() { body_parts.push(s); }
            }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    if !body_parts.is_empty() {
        footnote.body = Some(body_parts.join(" "));
    }

    Ok(footnote)
}

// ─── Abstract ────────────────────────────────────────────────────────────────

fn parse_abstract(pair: Pair<Rule>) -> Result<(String, Option<Vec<String>>), ParseError> {
    let mut text = String::new();
    let mut keywords: Option<Vec<String>> = None;

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::abstract_inner => {
                for attr in inner.into_inner() {
                    match attr.as_rule() {
                        Rule::abstract_keywords => { keywords = Some(extract_string_array(attr)?); }
                        Rule::abstract_content => {
                            let s = attr.as_str().trim();
                            if !s.is_empty() { text = s.to_string(); }
                        }
                        Rule::NEWLINE => {}
                        _ => {}
                    }
                }
            }
            Rule::abstract_keywords => { keywords = Some(extract_string_array(inner)?); }
            Rule::abstract_content => {
                let s = inner.as_str().trim();
                if !s.is_empty() { text = s.to_string(); }
            }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    Ok((text, keywords))
}

// ─── Sections ────────────────────────────────────────────────────────────────

fn parse_section(pair: Pair<Rule>, level: u8) -> Result<Section, ParseError> {
    let mut section = Section::new(level, "");

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::section_title => {
                section.title = inner.as_str().trim().to_string();
            }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    Ok(section)
}

// ─── Figure ─────────────────────────────────────────────────────────────────

fn parse_figure(pair: Pair<Rule>) -> Result<Figure, ParseError> {
    let mut figure = Figure::new("");
    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::figure_attrs => {
                for attr in inner.into_inner() {
                    match attr.as_rule() {
                        Rule::figure_path => { figure.path = extract_quoted_string(attr)?; }
                        Rule::figure_caption => { figure.caption = Some(extract_quoted_string(attr)?); }
                        Rule::figure_label => { figure.label = Some(extract_quoted_string(attr)?); }
                        Rule::NEWLINE => {}
                        _ => {}
                    }
                }
            }
            Rule::figure_path => { figure.path = extract_quoted_string(inner)?; }
            Rule::figure_caption => { figure.caption = Some(extract_quoted_string(inner)?); }
            Rule::figure_label => { figure.label = Some(extract_quoted_string(inner)?); }
            Rule::NEWLINE => {}
            _ => {}
        }
    }
    Ok(figure)
}

// ─── Table ──────────────────────────────────────────────────────────────────

fn parse_table(pair: Pair<Rule>) -> Result<Table, ParseError> {
    let mut table = Table::new();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::table_attrs => {
                for attr in inner.into_inner() {
                    match attr.as_rule() {
                        Rule::table_caption => { table.caption = Some(extract_quoted_string(attr)?); }
                        Rule::table_label => { table.label = Some(extract_quoted_string(attr)?); }
                        Rule::table_columns => { table.columns = extract_string_array(attr)?; }
                        Rule::table_rows => { table.rows = extract_rows_array(attr)?; }
                        Rule::NEWLINE => {}
                        _ => {}
                    }
                }
            }
            Rule::table_caption => { table.caption = Some(extract_quoted_string(inner)?); }
            Rule::table_label => { table.label = Some(extract_quoted_string(inner)?); }
            Rule::table_columns => { table.columns = extract_string_array(inner)?; }
            Rule::table_rows => { table.rows = extract_rows_array(inner)?; }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    Ok(table)
}

// ─── Equation ────────────────────────────────────────────────────────────────

fn parse_equation(pair: Pair<Rule>) -> Result<Equation, ParseError> {
    let mut equation = Equation::new("");

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::equation_attrs => {
                for attr in inner.into_inner() {
                    match attr.as_rule() {
                        Rule::equation_content => { equation.content = extract_quoted_string(attr)?; }
                        Rule::equation_label => { equation.label = Some(extract_quoted_string(attr)?); }
                        Rule::NEWLINE => {}
                        _ => {}
                    }
                }
            }
            Rule::equation_content => { equation.content = extract_quoted_string(inner)?; }
            Rule::equation_label => { equation.label = Some(extract_quoted_string(inner)?); }
            Rule::NEWLINE => {}
            _ => {}
        }
    }

    Ok(equation)
}

// ─── Paragraph ───────────────────────────────────────────────────────────────

fn parse_paragraph(pair: Pair<Rule>) -> Result<Paragraph, ParseError> {
    let mut inlines = Vec::new();

    for inner in pair.into_inner() {
        if inner.as_rule() == Rule::paragraph_content {
            for elem in inner.into_inner() {
                match elem.as_rule() {
                    Rule::plain_text => {
                        inlines.push(Inline::Text {
                            value: elem.as_str().to_string(),
                        });
                    }
                    Rule::citation => {
                        for cite_inner in elem.into_inner() {
                            if cite_inner.as_rule() == Rule::cite_key {
                                inlines.push(Inline::Citation {
                                    key: cite_inner.as_str().to_string(),
                                });
                            }
                        }
                    }
                    Rule::reference => {
                        for ref_inner in elem.into_inner() {
                            if ref_inner.as_rule() == Rule::ref_target {
                                inlines.push(Inline::Reference {
                                    target: ref_inner.as_str().to_string(),
                                });
                            }
                        }
                    }
                    Rule::inline_math => {
                        for math_inner in elem.into_inner() {
                            if math_inner.as_rule() == Rule::math_content {
                                inlines.push(Inline::Math {
                                    content: math_inner.as_str().to_string(),
                                });
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    Ok(Paragraph::new(inlines))
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn extract_quoted_string(pair: Pair<Rule>) -> Result<String, ParseError> {
    for inner in pair.into_inner() {
        if inner.as_rule() == Rule::quoted_string {
            for s in inner.into_inner() {
                if s.as_rule() == Rule::inner_string {
                    return Ok(s.as_str().to_string());
                }
            }
        }
    }
    Ok(String::new())
}

fn extract_string_array(pair: Pair<Rule>) -> Result<Vec<String>, ParseError> {
    let mut result = Vec::new();

    for inner in pair.into_inner() {
        if inner.as_rule() == Rule::string_array {
            for item in inner.into_inner() {
                if item.as_rule() == Rule::quoted_string {
                    for s in item.into_inner() {
                        if s.as_rule() == Rule::inner_string {
                            result.push(s.as_str().to_string());
                        }
                    }
                }
            }
        }
    }

    Ok(result)
}

fn extract_rows_array(pair: Pair<Rule>) -> Result<Vec<Vec<String>>, ParseError> {
    let mut result = Vec::new();

    for inner in pair.into_inner() {
        if inner.as_rule() == Rule::rows_array {
            for row in inner.into_inner() {
                if row.as_rule() == Rule::string_array {
                    let mut row_values = Vec::new();
                    for item in row.into_inner() {
                        if item.as_rule() == Rule::quoted_string {
                            for s in item.into_inner() {
                                if s.as_rule() == Rule::inner_string {
                                    row_values.push(s.as_str().to_string());
                                }
                            }
                        }
                    }
                    result.push(row_values);
                }
            }
        }
    }

    Ok(result)
}

// ─── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_title() {
        let input = r#"@title{
  title = "My Paper"
}"#;
        let doc = parse(input).unwrap();
        assert_eq!(doc.meta.as_ref().unwrap().title.as_deref(), Some("My Paper"));
    }

    #[test]
    fn test_parse_author() {
        let input = r#"@title{
  @author{
    name = "Alice"
    affiliation = "MIT"
    email = "alice@mit.edu"
    corresponding = "true"
  }
}"#;
        let doc = parse(input).unwrap();
        let author = &doc.meta.as_ref().unwrap().authors[0];
        assert_eq!(author.name, "Alice");
        assert_eq!(author.affiliation.as_deref(), Some("MIT"));
        assert_eq!(author.email.as_deref(), Some("alice@mit.edu"));
        assert_eq!(author.corresponding, Some(true));
    }

    #[test]
    fn test_parse_footnote() {
        let input = r#"@title{
  @footnote{
    marker = "†"
    label = "equal_contribution"
    These authors contributed equally.
  }
}"#;
        let doc = parse(input).unwrap();
        let fn_ = &doc.meta.as_ref().unwrap().footnotes[0];
        assert_eq!(fn_.marker, "†");
        assert_eq!(fn_.label, "equal_contribution");
        assert_eq!(fn_.body.as_deref().unwrap().trim(), "These authors contributed equally.");
    }

    #[test]
    fn test_parse_abstract_with_keywords() {
        let input = r#"@abstract{
  keywords = ["AI", "ML"]
  This is the abstract text.
}"#;
        let doc = parse(input).unwrap();
        let meta = doc.meta.as_ref().unwrap();
        assert_eq!(meta.keywords, vec!["AI", "ML"]);
        assert_eq!(meta.abstract_text.as_deref(), Some("This is the abstract text."));
    }

    #[test]
    fn test_parse_section() {
        let input = "@section Introduction\n";
        let doc = parse(input).unwrap();
        if let Block::Section(s) = &doc.content[0] {
            assert_eq!(s.level, 1);
            assert_eq!(s.title, "Introduction");
        } else {
            panic!("expected section");
        }
    }

    #[test]
    fn test_parse_figure() {
        let input = r#"@figure{
  path = "fig1.png"
  caption = "Overview"
  label = "fig:overview"
}"#;
        let doc = parse(input).unwrap();
        if let Block::Figure(f) = &doc.content[0] {
            assert_eq!(f.path, "fig1.png");
            assert_eq!(f.caption.as_deref(), Some("Overview"));
            assert_eq!(f.label.as_deref(), Some("fig:overview"));
        } else {
            panic!("expected figure");
        }
    }

    #[test]
    fn test_parse_table() {
        let input = r#"@table{
  caption = "Results"
  label = "tab:results"
  columns = ["Method", "Score"]
  rows = [["Ours", "0.95"], ["Base", "0.80"]]
}"#;
        let doc = parse(input).unwrap();
        if let Block::Table(t) = &doc.content[0] {
            assert_eq!(t.columns, vec!["Method", "Score"]);
            assert_eq!(t.rows.len(), 2);
        } else {
            panic!("expected table");
        }
    }

    #[test]
    fn test_parse_equation() {
        let input = r#"@equation{
  content = "E = mc^2"
  label = "eq:einstein"
}"#;
        let doc = parse(input).unwrap();
        if let Block::Equation(e) = &doc.content[0] {
            assert_eq!(e.content, "E = mc^2");
            assert_eq!(e.label.as_deref(), Some("eq:einstein"));
        } else {
            panic!("expected equation");
        }
    }

    #[test]
    fn test_parse_paragraph_with_citation() {
        let input = "This is a test with @cite{ref2024} citation.\n";
        let doc = parse(input).unwrap();
        assert_eq!(doc.content.len(), 1);
        if let Block::Paragraph(p) = &doc.content[0] {
            assert!(p.content.iter().any(|i| matches!(i, Inline::Citation { key } if key == "ref2024")));
        } else {
            panic!("expected paragraph");
        }
    }

    #[test]
    fn test_parse_paragraph_starting_with_ref() {
        // Regression: @ref{...} at the very start of a line should still be parsed
        // as a paragraph (not rejected as "expected top-level block").
        let input = "@ref{fig:foo} shows qualitative comparisons.\n";
        let doc = parse(input).unwrap();
        assert_eq!(doc.content.len(), 1);
        if let Block::Paragraph(p) = &doc.content[0] {
            assert!(p.content.iter().any(|i| matches!(i, Inline::Reference { target } if target == "fig:foo")));
        } else {
            panic!("expected paragraph");
        }
    }
}

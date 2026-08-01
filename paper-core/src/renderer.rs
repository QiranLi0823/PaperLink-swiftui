//! HTML Renderer
//!
//! Renders a Document AST to HTML string.

use crate::ast::*;

/// Render a Document to HTML
pub fn render(doc: &Document) -> String {
    let mut html = String::new();
    html.push_str("<article class=\"paper\">\n");

    if let Some(ref meta) = doc.meta {
        html.push_str(&render_meta(meta));
    }

    for block in &doc.content {
        html.push_str(&render_block(block));
    }

    html.push_str("</article>\n");
    html
}

fn render_meta(meta: &Meta) -> String {
    let mut html = String::new();
    html.push_str("<header class=\"paper-header\">\n");

    if let Some(ref title) = meta.title {
        html.push_str(&format!(
            "  <h1 class=\"paper-title\">{}</h1>\n",
            escape_html(title)
        ));
    }

    // Render authors
    if !meta.authors.is_empty() {
        html.push_str("  <div class=\"paper-authors\">\n");
        for author in &meta.authors {
            html.push_str(&render_author(author, &meta.footnotes));
        }
        html.push_str("  </div>\n");
    }

    // Render footnotes at the bottom of header
    if !meta.footnotes.is_empty() {
        html.push_str("  <div class=\"paper-footnotes\">\n");
        for footnote in &meta.footnotes {
            html.push_str(&format!(
                "    <p class=\"footnote\"><sup>{}</sup> {}</p>\n",
                escape_html(&footnote.marker),
                escape_html(footnote.body.as_deref().unwrap_or(""))
            ));
        }
        html.push_str("  </div>\n");
    }

    html.push_str("</header>\n\n");
    html
}

fn render_author(author: &Author, footnotes: &[Footnote]) -> String {
    // Build superscripts for footnotes
    let mut superscripts = String::new();
    if let Some(ref note) = author.note {
        for fn_ in footnotes {
            if &fn_.label == note {
                superscripts.push_str(&format!("<sup>{}</sup>", escape_html(&fn_.marker)));
            }
        }
    }
    if author.corresponding == Some(true) {
        for fn_ in footnotes {
            if fn_.label == "corresponding" {
                superscripts.push_str(&format!("<sup>{}</sup>", escape_html(&fn_.marker)));
            }
        }
    }

    let mut parts: Vec<String> = vec![format!(
        "{}{}",
        escape_html(&author.name),
        superscripts
    )];

    if let Some(ref aff) = author.affiliation {
        parts.push(format!("<span class=\"author-affil\">{}</span>", escape_html(aff)));
    }

    let email_link = author.email.as_ref().map(|e| {
        format!(" <a class=\"author-email\" href=\"mailto:{}\">✉</a>", escape_html(e))
    }).unwrap_or_default();

    format!(
        "    <span class=\"author\">{}</span>\n",
        parts.join("<br>") + &email_link
    )
}

fn render_block(block: &Block) -> String {
    match block {
        Block::Section(s) => render_section(s),
        Block::Paragraph(p) => render_paragraph(p),
        Block::Figure(f) => render_figure(f),
        Block::Table(t) => render_table(t),
        Block::Equation(e) => render_equation(e),
    }
}

fn render_section(section: &Section) -> String {
    let tag = format!("h{}", (section.level + 1).min(6));
    let id_attr = section
        .label
        .as_ref()
        .map(|l| format!(" id=\"{}\"", escape_html(l)))
        .unwrap_or_default();

    let mut html = format!(
        "<{}{} class=\"section-title\">{}</{}>\n",
        tag,
        id_attr,
        escape_html(&section.title),
        tag
    );

    for child in &section.children {
        html.push_str(&render_block(child));
    }

    html
}

fn render_paragraph(para: &Paragraph) -> String {
    let mut content = String::new();
    for inline in &para.content {
        content.push_str(&render_inline(inline));
    }
    format!("<p>{}</p>\n", content)
}

fn render_inline(inline: &Inline) -> String {
    match inline {
        Inline::Text { value } => escape_html(value),
        Inline::Citation { key } => {
            format!(
                "<cite class=\"citation\" data-key=\"{}\">[{}]</cite>",
                escape_html(key),
                escape_html(key)
            )
        }
        Inline::Reference { target } => {
            format!(
                "<a href=\"#{}\" class=\"reference\">{}</a>",
                escape_html(target),
                escape_html(target)
            )
        }
        Inline::Math { content } => {
            format!("<span class=\"math inline\">\\({}\\)</span>", escape_html(content))
        }
        Inline::Bold { content } => {
            let inner: String = content.iter().map(render_inline).collect();
            format!("<strong>{}</strong>", inner)
        }
        Inline::Italic { content } => {
            let inner: String = content.iter().map(render_inline).collect();
            format!("<em>{}</em>", inner)
        }
    }
}

fn render_figure(fig: &Figure) -> String {
    let id_attr = fig
        .label
        .as_ref()
        .map(|l| format!(" id=\"{}\"", escape_html(l)))
        .unwrap_or_default();

    let caption_html = fig
        .caption
        .as_ref()
        .map(|c| format!("  <figcaption>{}</figcaption>\n", escape_html(c)))
        .unwrap_or_default();

    format!(
        "<figure{}>\n  <img src=\"{}\" alt=\"{}\" loading=\"lazy\">\n{}</figure>\n",
        id_attr,
        escape_html(&fig.path),
        fig.caption.as_deref().map(escape_html).unwrap_or_default(),
        caption_html
    )
}

fn render_table(table: &Table) -> String {
    let id_attr = table
        .label
        .as_ref()
        .map(|l| format!(" id=\"{}\"", escape_html(l)))
        .unwrap_or_default();

    let mut html = format!("<figure class=\"table-container\"{}>\n", id_attr);

    if let Some(ref caption) = table.caption {
        html.push_str(&format!("  <figcaption>{}</figcaption>\n", escape_html(caption)));
    }

    html.push_str("  <table>\n");

    if !table.columns.is_empty() {
        html.push_str("    <thead>\n      <tr>\n");
        for col in &table.columns {
            html.push_str(&format!("        <th>{}</th>\n", escape_html(col)));
        }
        html.push_str("      </tr>\n    </thead>\n");
    }

    if !table.rows.is_empty() {
        html.push_str("    <tbody>\n");
        for row in &table.rows {
            html.push_str("      <tr>\n");
            for cell in row {
                html.push_str(&format!("        <td>{}</td>\n", escape_html(cell)));
            }
            html.push_str("      </tr>\n");
        }
        html.push_str("    </tbody>\n");
    }

    html.push_str("  </table>\n</figure>\n");
    html
}

fn render_equation(eq: &Equation) -> String {
    let id_attr = eq
        .label
        .as_ref()
        .map(|l| format!(" id=\"{}\"", escape_html(l)))
        .unwrap_or_default();

    format!(
        "<div class=\"equation\"{}>\n  \\[{}\\]\\n</div>\\n",
        id_attr,
        escape_html(&eq.content)
    )
}

/// Escape HTML special characters
fn escape_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_render_section() {
        let section = Section::new(1, "Introduction");
        let html = render_section(&section);
        assert!(html.contains("<h2"));
        assert!(html.contains("Introduction"));
    }

    #[test]
    fn test_render_paragraph() {
        let para = Paragraph::from_text("Hello world");
        let html = render_paragraph(&para);
        assert_eq!(html, "<p>Hello world</p>\n");
    }

    #[test]
    fn test_escape_html() {
        assert_eq!(escape_html("<script>"), "&lt;script&gt;");
        assert_eq!(escape_html("a & b"), "a &amp; b");
    }

    #[test]
    fn test_render_figure() {
        let mut fig = Figure::new("fig.png");
        fig.caption = Some("Test".to_string());
        fig.label = Some("fig:test".to_string());
        let html = render_figure(&fig);
        assert!(html.contains("fig.png"));
        assert!(html.contains("fig:test"));
    }

    #[test]
    fn test_render_author() {
        let mut author = Author::new("Alice");
        author.affiliation = Some("MIT".to_string());
        author.corresponding = Some(true);
        let footnotes = vec![Footnote::new("*", "corresponding")];
        let html = render_author(&author, &footnotes);
        assert!(html.contains("Alice"));
        assert!(html.contains("MIT"));
        assert!(html.contains("sup>*"));
    }
}

//! Paper Core - PaperML Parser and Renderer
//!
//! This crate provides the core functionality for Paper Studio:
//! - PaperML parsing (pest-based)
//! - AST representation
//! - HTML rendering

use wasm_bindgen::prelude::*;

pub mod ast;
pub mod parser;
pub mod renderer;

/// Parse PaperML and render to HTML
#[wasm_bindgen]
pub fn parse_and_render(input: &str) -> Result<String, JsValue> {
    let doc = parser::parse(input).map_err(|e| JsValue::from_str(&e.to_string()))?;
    Ok(renderer::render(&doc))
}

/// Parse PaperML to JSON (AST representation)
#[wasm_bindgen]
pub fn parse_to_json(input: &str) -> Result<String, JsValue> {
    let doc = parser::parse(input).map_err(|e| JsValue::from_str(&e.to_string()))?;
    serde_json::to_string_pretty(&doc).map_err(|e| JsValue::from_str(&e.to_string()))
}

/// Get version information
#[wasm_bindgen]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

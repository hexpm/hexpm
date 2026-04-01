defmodule HexpmWeb.ReadmeView do
  use HexpmWeb, :view

  @makeup_css File.read!("assets/vendor/css/makeup.css")

  def readme_css do
    ~S"""
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { overflow: hidden; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; font-size: 16px; line-height: 1.6; color: #24292e; padding: 0; }
    .readme { max-width: 100%; overflow-wrap: break-word; word-wrap: break-word; }
    .readme h1, .readme h2, .readme h3, .readme h4, .readme h5, .readme h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
    .readme h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #eaecef; }
    .readme h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #eaecef; }
    .readme h3 { font-size: 1.25em; }
    .readme h4 { font-size: 1em; }
    .readme p { margin-top: 0; margin-bottom: 16px; }
    .readme a { color: #0366d6; text-decoration: none; }
    .readme a:hover { text-decoration: underline; }
    .readme img { max-width: 100%; height: auto; margin: 2px; }
    .readme pre { padding: 1rem; overflow-x: auto; background-color: #111827; border-radius: 0.5rem; margin-bottom: 1rem; }
    .readme code { padding: 0.125rem 0.375rem; font-size: 0.875rem; background-color: #f3f4f6; border-radius: 0.25rem; font-family: ui-monospace, monospace; color: #1f2937; }
    .readme pre code { padding: 0; background: transparent; font-size: 0.875rem; color: #e5e7eb; }
    .readme blockquote { padding: 0 1em; color: #6a737d; border-left: 0.25em solid #dfe2e5; margin-bottom: 16px; }
    .readme ul, .readme ol { padding-left: 2em; margin-bottom: 16px; }
    .readme li { margin-top: 0.25em; }
    .readme table { border-collapse: collapse; border-spacing: 0; margin-bottom: 16px; display: block; width: max-content; max-width: 100%; overflow: auto; }
    .readme table th, .readme table td { padding: 6px 13px; border: 1px solid #dfe2e5; }
    .readme table th { font-weight: 600; background-color: #f6f8fa; }
    .readme table tr:nth-child(2n) { background-color: #f6f8fa; }
    .readme hr { height: 0.25em; padding: 0; margin: 24px 0; background-color: #e1e4e8; border: 0; }
    .readme details { margin-bottom: 16px; }
    .readme details summary { cursor: pointer; font-weight: 600; }
    .readme dl { padding: 0; margin-bottom: 16px; }
    .readme dl dt { padding: 0; margin-top: 16px; font-size: 1em; font-style: italic; font-weight: 600; }
    .readme dl dd { padding: 0 16px; margin-bottom: 16px; }
    .readme kbd { display: inline-block; padding: 3px 5px; font: 11px ui-monospace, monospace; line-height: 10px; color: #444d56; vertical-align: middle; background-color: #fafbfc; border: 1px solid #d1d5da; border-radius: 3px; box-shadow: inset 0 -1px 0 #d1d5da; }
    .readme input[type="checkbox"] { margin-right: 0.5em; }
    .readme li:has(> input[type="checkbox"]) { list-style: none; }
    .color-scheme-dark { display: none !important; }
    """
  end

  def makeup_css, do: @makeup_css
end

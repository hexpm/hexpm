defmodule HexpmWeb.ReadmeView do
  use HexpmWeb, :view

  @makeup_css File.read!("assets/vendor/css/makeup.css")

  def readme_css do
    ~S"""
    :root {
      --color-blue-600: #0f59d8;
      --color-blue-300: #9fbdef;
      --color-grey-900: #030913;
      --color-grey-800: #0d1829;
      --color-grey-700: #1c2a3a;
      --color-grey-600: #304254;
      --color-grey-500: #445668;
      --color-grey-300: #91a4b7;
      --color-grey-200: #cad5e0;
      --color-grey-100: #e1e8f0;
      --color-grey-50: #f0f5f9;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { overflow: hidden; }
    html { color-scheme: light; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; font-size: 16px; line-height: 1.6; color: var(--color-grey-700); padding: 0; }
    .readme { max-width: 100%; overflow-wrap: break-word; word-wrap: break-word; }
    .readme h1, .readme h2, .readme h3, .readme h4, .readme h5, .readme h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
    .readme h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--color-grey-100); }
    .readme h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--color-grey-100); }
    .readme h3 { font-size: 1.25em; }
    .readme h4 { font-size: 1em; }
    .readme p { margin-top: 0; margin-bottom: 16px; }
    .readme a { color: var(--color-blue-600); text-decoration: none; }
    .readme a:hover { text-decoration: underline; }
    .readme img { max-width: 100%; height: auto; margin: 2px; }
    .readme pre { padding: 1rem; overflow-x: auto; background-color: var(--color-grey-900); border-radius: 0.5rem; margin-bottom: 1rem; }
    .readme .highlight,
    .readme .highlight pre { background: var(--color-grey-900); }
    .readme code { padding: 0.125rem 0.375rem; font-size: 0.875rem; background-color: var(--color-grey-50); border-radius: 0.25rem; font-family: ui-monospace, monospace; color: var(--color-grey-800); }
    .readme pre code { padding: 0; background: transparent; font-size: 0.875rem; color: var(--color-grey-100); }
    .readme blockquote { padding: 0 1em; color: var(--color-grey-500); border-left: 0.25em solid var(--color-grey-100); margin-bottom: 16px; }
    .readme ul, .readme ol { padding-left: 2em; margin-bottom: 16px; }
    .readme li { margin-top: 0.25em; }
    .readme table { border-collapse: collapse; border-spacing: 0; margin-bottom: 16px; display: block; width: max-content; max-width: 100%; overflow: auto; }
    .readme table th, .readme table td { padding: 6px 13px; border: 1px solid var(--color-grey-100); }
    .readme table th { font-weight: 600; background-color: var(--color-grey-50); }
    .readme table tr:nth-child(2n) { background-color: var(--color-grey-50); }
    .readme hr { height: 0.25em; padding: 0; margin: 24px 0; background-color: var(--color-grey-100); border: 0; }
    .readme details { margin-bottom: 16px; }
    .readme details summary { cursor: pointer; font-weight: 600; }
    .readme dl { padding: 0; margin-bottom: 16px; }
    .readme dl dt { padding: 0; margin-top: 16px; font-size: 1em; font-style: italic; font-weight: 600; }
    .readme dl dd { padding: 0 16px; margin-bottom: 16px; }
    .readme kbd { display: inline-block; padding: 3px 5px; font: 11px ui-monospace, monospace; line-height: 10px; color: var(--color-grey-500); vertical-align: middle; background-color: white; border: 1px solid var(--color-grey-200); border-radius: 3px; box-shadow: inset 0 -1px 0 var(--color-grey-200); }
    .readme input[type="checkbox"] { margin-right: 0.5em; }
    .readme li:has(> input[type="checkbox"]) { list-style: none; }
    html[data-theme="light"] .color-scheme-dark { display: none !important; }
    html[data-theme="dark"] .color-scheme-light { display: none !important; }
    html[data-theme="dark"] body { color: var(--color-grey-200); background-color: var(--color-grey-800); }
    html[data-theme="dark"] .readme h1, html[data-theme="dark"] .readme h2 { border-bottom-color: var(--color-grey-600); }
    html[data-theme="dark"] .readme a { color: var(--color-blue-300); }
    html[data-theme="dark"] .readme code:not(pre code) { background-color: var(--color-grey-900); color: var(--color-grey-100); }
    html[data-theme="dark"] .readme pre { background-color: var(--color-grey-900); }
    html[data-theme="dark"] .readme .highlight,
    html[data-theme="dark"] .readme .highlight pre { background: var(--color-grey-900); }
    html[data-theme="dark"] .readme pre code { background-color: transparent; color: var(--color-grey-100); }
    html[data-theme="dark"] .readme blockquote { color: var(--color-grey-300); border-left-color: var(--color-grey-500); }
    html[data-theme="dark"] .readme table th, html[data-theme="dark"] .readme table td { border-color: var(--color-grey-600); }
    html[data-theme="dark"] .readme table th, html[data-theme="dark"] .readme table tr:nth-child(2n) { background-color: var(--color-grey-800); }
    html[data-theme="dark"] .readme hr { background-color: var(--color-grey-600); }
    html[data-theme="dark"] .readme kbd { color: var(--color-grey-100); background-color: var(--color-grey-700); border-color: var(--color-grey-500); box-shadow: inset 0 -1px 0 var(--color-grey-500); }
    """
  end

  def makeup_css, do: @makeup_css
end

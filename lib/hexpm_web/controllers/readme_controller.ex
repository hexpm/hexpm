defmodule HexpmWeb.ReadmeController do
  use HexpmWeb, :controller

  alias HexpmWeb.Readme.{Sanitizer, URLRewriter}

  @readme_extensions ~w(.md .markdown .txt)

  @highlight_css File.read!("assets/vendor/css/github.css")
  @highlight_js File.read!("assets/vendor/js/highlight.js/highlight.min.js")

  @highlight_languages Enum.map_join(
                         ~w(elixir erlang rust go ruby),
                         "\n",
                         &File.read!(
                           "assets/vendor/js/highlight.js/languages/highlight.lang.#{&1}.min.js"
                         )
                       )

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
  end

  def show(conn, params) do
    name = params["name"]
    version = params["version"]

    package = Packages.get("hexpm", name)

    if package do
      releases = Releases.all(package)

      release =
        if version do
          Enum.find(releases, &(to_string(&1.version) == version))
        else
          Hexpm.Repository.Release.latest_version(releases,
            only_stable: true,
            unstable_fallback: true
          )
        end

      if release do
        serve_readme(conn, package, release)
      else
        send_no_readme(conn)
      end
    else
      send_no_readme(conn)
    end
  end

  defp serve_readme(conn, package, release) do
    version = to_string(release.version)

    case fetch_readme(package.name, version) do
      {:ok, filename, content} ->
        html = render_readme(filename, content, package.name, version)

        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_content_type("text/html")
        |> send_resp(200, readme_page(conn, html))

      :error ->
        send_no_readme(conn)
    end
  end

  defp fetch_readme(package_name, version) do
    preview_url = Application.fetch_env!(:hexpm, :preview_url)
    file_list_url = "#{preview_url}/preview/file_lists/#{package_name}-#{version}.json"

    with {:ok, 200, _headers, body} <- Hexpm.HTTP.impl().get(file_list_url, []),
         {:ok, files} <- Jason.decode(body),
         {:ok, filename} <- find_readme(files) do
      readme_url = "#{preview_url}/preview/files/#{package_name}/#{version}/#{filename}"

      case Hexpm.HTTP.impl().get(readme_url, []) do
        {:ok, 200, _headers, content} -> {:ok, filename, content}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp find_readme(files) do
    case Enum.find(files, &readme?/1) do
      nil -> :error
      filename -> {:ok, filename}
    end
  end

  defp readme?(filename) do
    basename = Path.basename(filename, Path.extname(filename))
    ext = Path.extname(filename) |> String.downcase()
    String.downcase(basename) == "readme" and (ext == "" or ext in @readme_extensions)
  end

  defp render_readme(filename, content, package_name, version) do
    ext = Path.extname(filename) |> String.downcase()

    html =
      case ext do
        ext when ext in [".md", ".markdown"] ->
          Earmark.as_html!(content, %Earmark.Options{gfm: true})

        _ ->
          "<pre>#{Plug.HTML.html_escape(content)}</pre>"
      end

    html
    |> Sanitizer.sanitize()
    |> URLRewriter.rewrite(package_name, version)
  end

  defp send_no_readme(conn) do
    nonce = conn.assigns[:readme_csp_nonce] || ""

    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="utf-8"></head>
    <body>
      <script nonce="#{nonce}">
        window.parent.postMessage({type: 'readme-not-found'}, '*');
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  defp readme_page(conn, content_html) do
    nonce = conn.assigns[:readme_csp_nonce] || ""

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style nonce="#{nonce}">#{readme_css()}</style>
      <style nonce="#{nonce}">#{@highlight_css}</style>
    </head>
    <body>
      <article class="readme">
        #{content_html}
      </article>
      <script nonce="#{nonce}">#{@highlight_js}</script>
      <script nonce="#{nonce}">#{@highlight_languages}</script>
      <script nonce="#{nonce}">#{highlight_init_js()}</script>
    </body>
    </html>
    """
  end

  defp readme_css do
    ~S"""
    * { margin: 0; padding: 0; box-sizing: border-box; }
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
    .readme img { max-width: 100%; height: auto; }
    .readme pre { padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; background-color: #f6f8fa; border-radius: 6px; margin-bottom: 16px; }
    .readme code { padding: 0.2em 0.4em; font-size: 85%; background-color: #f6f8fa; border-radius: 3px; font-family: SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace; }
    .readme pre code { padding: 0; background: transparent; font-size: 100%; }
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
    .readme kbd { display: inline-block; padding: 3px 5px; font: 11px SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace; line-height: 10px; color: #444d56; vertical-align: middle; background-color: #fafbfc; border: 1px solid #d1d5da; border-radius: 3px; box-shadow: inset 0 -1px 0 #d1d5da; }
    .readme input[type="checkbox"] { margin-right: 0.5em; }
    """
  end

  defp highlight_init_js do
    ~S"""
    document.addEventListener('DOMContentLoaded', function() {
      if (typeof hljs !== 'undefined') {
        hljs.highlightAll();
      }
      function sendHeight() {
        window.parent.postMessage({type: 'readme-height', height: document.body.scrollHeight}, '*');
      }
      sendHeight();
      new ResizeObserver(sendHeight).observe(document.body);
    });
    """
  end
end

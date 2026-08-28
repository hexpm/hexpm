defmodule HexpmWeb.ReadmeController do
  use HexpmWeb, :controller

  alias HexpmWeb.Docs.Files
  alias HexpmWeb.Readme.{Sanitizer, TaskList, URLRewriter}

  @max_doc_size 2 * 1024 * 1024

  plug :put_root_layout, false
  plug :put_layout, false

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
  end

  def show(conn, params), do: serve(conn, params, :readme)

  def show_doc(conn, params) do
    case Files.parse_segment(conn.assigns.doc_kind) do
      nil -> not_found(conn, params)
      kind -> serve(conn, params, kind)
    end
  end

  defp serve(conn, %{"version" => version} = params, kind) do
    name = params["name"]
    package = Packages.get("hexpm", name)

    if package do
      release = Enum.find(Releases.all(package), &(to_string(&1.version) == version))

      if release do
        serve_doc(conn, package, release, kind)
      else
        send_not_found(conn, [])
      end
    else
      send_not_found(conn, [])
    end
  end

  defp serve(conn, params, kind) do
    name = params["name"]
    package = Packages.get("hexpm", name)

    if package do
      releases = Releases.all(package)

      release =
        Hexpm.Repository.Release.latest_version(releases,
          only_stable: true,
          unstable_fallback: true
        )

      if release do
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> redirect(to: doc_path(name, release.version, kind))
      else
        send_not_found(conn, [])
      end
    else
      send_not_found(conn, [])
    end
  end

  defp doc_path(name, version, :readme), do: "/#{name}/#{version}"
  defp doc_path(name, version, kind), do: "/#{name}/#{version}/#{kind}"

  defp serve_doc(conn, package, release, kind) do
    version = to_string(release.version)

    case fetch_doc(package.name, version, kind) do
      {:ok, filename, content, available} ->
        html =
          if byte_size(content) > @max_doc_size do
            too_large_notice(filename, package.name, version)
          else
            render_doc(filename, content, package.name, version)
          end

        render_show(conn, html, filename, available)

      {:error, :too_large, filename, available} ->
        html = too_large_notice(filename, package.name, version)
        render_show(conn, html, filename, available)

      {:error, :not_found, available} ->
        send_not_found(conn, available, cacheable: true)

      {:error, :upstream_error, available} ->
        send_not_found(conn, available, cacheable: false)
    end
  end

  defp render_show(conn, html, filename, available) do
    conn
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> render(:show,
      readme_html: html,
      parent_origins: parent_origins(),
      doc_kinds: Enum.map(available, &Atom.to_string/1),
      doc_source: filename
    )
  end

  defp too_large_notice(filename, package_name, version) do
    preview_url = Hexpm.Utils.preview_html_url(package_name, version)
    escaped_filename = Plug.HTML.html_escape(filename)
    escaped_url = Plug.HTML.html_escape(preview_url)

    "<p>#{escaped_filename} is too large to display on Hex.pm. " <>
      "<a href=\"#{escaped_url}\">View it in the file browser</a>.</p>"
  end

  defp fetch_doc(package_name, version, kind) do
    cdn_url = Application.fetch_env!(:hexpm, :cdn_url)
    file_list_url = "#{cdn_url}/preview-files/#{package_name}-#{version}.json"

    case Hexpm.HTTP.impl().get(file_list_url, []) do
      {:ok, 200, _headers, body} ->
        case decode_file_list(body) do
          {:ok, files} ->
            resolved = Files.resolve_all(files)
            available = Files.present_kinds(resolved)

            case Map.get(resolved, kind) do
              nil -> {:error, :not_found, available}
              filename -> fetch_document(cdn_url, package_name, version, filename, available)
            end

          :error ->
            {:error, :not_found, []}
        end

      {:ok, status, _headers, _body} when status in 500..599 ->
        {:error, :upstream_error, []}

      {:ok, _status, _headers, _body} ->
        {:error, :not_found, []}

      {:error, _reason} ->
        {:error, :upstream_error, []}
    end
  end

  defp decode_file_list(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end

  defp decode_file_list(body), do: {:ok, body}

  defp fetch_document(cdn_url, package_name, version, filename, available) do
    doc_url = "#{cdn_url}/preview/#{package_name}/#{version}/#{filename}"

    case Hexpm.HTTP.impl().get(doc_url, [], max_body_size: @max_doc_size) do
      {:ok, 200, _headers, content} ->
        {:ok, filename, content, available}

      {:error, :body_too_large} ->
        {:error, :too_large, filename, available}

      {:ok, status, _headers, _body} when status in 500..599 ->
        {:error, :upstream_error, available}

      {:ok, _status, _headers, _body} ->
        {:error, :not_found, available}

      {:error, _reason} ->
        {:error, :upstream_error, available}
    end
  end

  defp render_doc(filename, content, package_name, version) do
    ext = Path.extname(filename) |> String.downcase()

    html =
      case ext do
        ext when ext in [".md", ".markdown"] ->
          {_status, ast, _messages} = Earmark.Parser.as_ast(content, gfm: true)
          ast |> TaskList.convert() |> Earmark.transform()

        _ ->
          "<pre>#{Plug.HTML.html_escape(content)}</pre>"
      end

    html
    |> Sanitizer.sanitize()
    |> URLRewriter.rewrite(package_name, version)
    |> highlight_code_blocks()
  end

  # Highlighting runs after sanitization since Makeup output is generated
  # code that doesn't need sanitizing, and the sanitizer's Floki round-trip
  # strips whitespace from inline elements (breaking newlines in code).
  defp highlight_code_blocks(html) do
    Regex.replace(
      ~r{<pre><code class="([\w-]+)">(.*?)</code></pre>}s,
      html,
      fn full_match, lang, code ->
        language =
          if String.starts_with?(lang, "language-"),
            do: String.trim_leading(lang, "language-"),
            else: lang

        case Makeup.Registry.fetch_lexer_by_name(language) do
          {:ok, {lexer, opts}} ->
            code |> unescape_html() |> Makeup.highlight(lexer: lexer, lexer_options: opts)

          :error ->
            full_match
        end
      end
    )
  end

  defp unescape_html(html) do
    html
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp send_not_found(conn, available, opts \\ []) do
    cache_control =
      if Keyword.get(opts, :cacheable, true) do
        "public, max-age=3600"
      else
        "no-store"
      end

    conn
    |> put_resp_header("cache-control", cache_control)
    |> render(:no_readme,
      parent_origins: parent_origins(),
      doc_kinds: Enum.map(available, &Atom.to_string/1)
    )
  end

  defp parent_origins do
    case Application.get_env(:hexpm, :host) do
      nil -> ["*"]
      # TODO: Remove new.hex.pm when new.hex.pm replaces hex.pm
      host -> ["https://#{host}", "https://new.#{host}"]
    end
  end
end

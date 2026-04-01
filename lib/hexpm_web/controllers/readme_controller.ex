defmodule HexpmWeb.ReadmeController do
  use HexpmWeb, :controller

  alias HexpmWeb.Readme.{Sanitizer, TaskList, URLRewriter}

  @readme_filenames ~w(README.md readme.md README.markdown readme.markdown README.txt readme.txt README readme)

  plug :put_root_layout, false
  plug :put_layout, false

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
  end

  def show(conn, %{"version" => version} = params) do
    name = params["name"]
    package = Packages.get("hexpm", name)

    if package do
      release = Enum.find(Releases.all(package), &(to_string(&1.version) == version))

      if release do
        serve_readme(conn, package, release)
      else
        send_no_readme(conn)
      end
    else
      send_no_readme(conn)
    end
  end

  def show(conn, params) do
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
        |> redirect(to: "/#{name}/#{release.version}")
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
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> render(:show, readme_html: html, parent_origins: parent_origins())

      :error ->
        send_no_readme(conn)
    end
  end

  defp fetch_readme(package_name, version) do
    cdn_url = Application.fetch_env!(:hexpm, :cdn_url)
    file_list_url = "#{cdn_url}/preview-files/#{package_name}-#{version}.json"

    case Hexpm.HTTP.impl().get(file_list_url, []) do
      {:ok, 200, _headers, json} ->
        files = Jason.decode!(json)

        case find_readme_file(files) do
          nil ->
            :error

          filename ->
            readme_url = "#{cdn_url}/preview/#{package_name}/#{version}/#{filename}"

            case Hexpm.HTTP.impl().get(readme_url, []) do
              {:ok, 200, _headers, content} -> {:ok, filename, content}
              _ -> :error
            end
        end

      _ ->
        :error
    end
  end

  defp find_readme_file(files) do
    Enum.find(@readme_filenames, &(&1 in files))
  end

  defp render_readme(filename, content, package_name, version) do
    ext = Path.extname(filename) |> String.downcase()

    html =
      case ext do
        ext when ext in [".md", ".markdown"] ->
          {:ok, ast, _messages} = Earmark.Parser.as_ast(content, gfm: true)
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
  end

  defp send_no_readme(conn) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> render(:no_readme, parent_origins: parent_origins())
  end

  defp parent_origins do
    case Application.get_env(:hexpm, :host) do
      nil -> ["*"]
      # TODO: Remove new.hex.pm when new.hex.pm replaces hex.pm
      host -> ["https://#{host}", "https://new.#{host}"]
    end
  end
end

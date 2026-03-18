defmodule HexpmWeb.ReadmeController do
  use HexpmWeb, :controller

  alias HexpmWeb.Readme.{Sanitizer, URLRewriter}

  @readme_filenames ~w(README.md readme.md README.markdown readme.markdown README.txt readme.txt README readme)

  plug :put_root_layout, false
  plug :put_layout, false

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
        |> render(:show, readme_html: html, parent_origins: parent_origins())

      :error ->
        send_no_readme(conn)
    end
  end

  defp fetch_readme(package_name, version) do
    case Hexpm.Store.get(:repo_bucket, "file_lists/#{package_name}-#{version}.json", []) do
      nil ->
        :error

      json ->
        files = Jason.decode!(json)

        case find_readme_file(files) do
          nil ->
            :error

          filename ->
            case Hexpm.Store.get(
                   :repo_bucket,
                   "files/#{package_name}/#{version}/#{filename}",
                   []
                 ) do
              nil -> :error
              content -> {:ok, filename, content}
            end
        end
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
          Earmark.as_html!(content, %Earmark.Options{gfm: true})

        _ ->
          "<pre>#{Plug.HTML.html_escape(content)}</pre>"
      end

    html
    |> Sanitizer.sanitize()
    |> URLRewriter.rewrite(package_name, version)
    |> highlight_code_blocks()
  end

  defp highlight_code_blocks(html) do
    html
    |> Floki.parse_fragment!()
    |> highlight_nodes()
    |> Floki.raw_html()
  end

  defp highlight_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &highlight_node/1)
  end

  defp highlight_node({"pre", _pre_attrs, [{"code", code_attrs, children}]} = node) do
    language = extract_language(code_attrs)

    with language when is_binary(language) <- language,
         {:ok, {lexer, opts}} <- Makeup.Registry.fetch_lexer_by_name(language) do
      code_text = Floki.text({"code", code_attrs, children})
      highlighted_html = Makeup.highlight(code_text, lexer: lexer, lexer_options: opts)
      Floki.parse_fragment!(highlighted_html)
    else
      _ -> [node]
    end
  end

  defp highlight_node({tag, attrs, children}) do
    [{tag, attrs, highlight_nodes(children)}]
  end

  defp highlight_node(other), do: [other]

  defp extract_language(attrs) do
    case List.keyfind(attrs, "class", 0) do
      {"class", class} ->
        parts = String.split(class)

        Enum.find_value(parts, fn
          "language-" <> lang -> lang
          _ -> nil
        end) ||
          case parts do
            [single] -> single
            _ -> nil
          end

      nil ->
        nil
    end
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

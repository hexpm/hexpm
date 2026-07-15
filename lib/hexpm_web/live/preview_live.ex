defmodule HexpmWeb.PreviewLive do
  use HexpmWeb, :live_view

  require Logger

  @highlight_timeout 1_000

  defmodule NotFoundError do
    defexception message: "Preview source not found", plug_status: 404
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       package: params["package"],
       version: nil,
       files: [],
       filename: nil,
       highlighted: nil,
       message: nil,
       title: "Package preview",
       description: nil,
       canonical_url: nil,
       container: "container"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    package = params["package"]
    version = params["version"] || Hexpm.Preview.get_latest_version(package)
    requested_filename = filename(params["filename"])

    with version when is_binary(version) <- version,
         {:ok, source} <- Hexpm.Preview.source(package, version, requested_filename) do
      {:noreply, assign_source(socket, package, version, source)}
    else
      _ -> raise NotFoundError
    end
  end

  @impl true
  def handle_event("select_file", %{"file" => filename}, socket) do
    {:noreply, push_patch(socket, to: preview_path(socket, filename), replace: true)}
  end

  defp assign_source(socket, package, version, source) do
    {highlighted, message} = render_contents(package, version, source)
    filename = source.filename

    assign(socket,
      package: package,
      version: version,
      files: source.files,
      filename: filename,
      highlighted: highlighted,
      message: message,
      title: "#{filename} - #{package} #{version}",
      description: description(package, version, filename),
      canonical_url: canonical_url(socket, package, version, filename)
    )
  end

  defp render_contents(package, version, %{type: :text} = source) do
    {highlight(package, version, source.filename, source.contents), nil}
  end

  defp render_contents(_package, _version, %{type: :binary}) do
    {nil, "Contents for binary files are not shown."}
  end

  defp render_contents(_package, _version, %{type: {:too_large, size}}) do
    {nil, "File is too large to be displayed (#{Float.round(size / 1_000_000, 1)} MB)."}
  end

  defp highlight(package, version, filename, contents) do
    task =
      Task.Supervisor.async_nolink(Hexpm.Tasks, fn ->
        Lumis.highlight!(contents, formatter: {:html_linked, language: filename})
      end)

    case Task.yield(task, @highlight_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, highlighted} ->
        highlighted

      result ->
        Logger.warning(
          "Failed to highlight Preview source #{package} #{version} #{filename}: #{inspect(result)}"
        )

        plain_source(contents)
    end
  end

  defp plain_source(contents) do
    lines =
      contents
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join(fn {line, number} ->
        escaped = line |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        ~s(<div class="l-line" data-line="#{number}">#{escaped}</div>)
      end)

    ~s(<pre class="lumis"><code>#{lines}</code></pre>)
  end

  defp filename([_ | _] = parts), do: Path.join(parts)
  defp filename(filename) when is_binary(filename) and filename != "", do: filename
  defp filename(_filename), do: nil

  defp preview_path(%{assigns: %{live_action: :latest, package: package}}, filename) do
    ~p"/preview/#{package}/show/#{Path.split(filename)}"
  end

  defp preview_path(
         %{assigns: %{package: package, version: version}},
         filename
       ) do
    ~p"/preview/#{package}/#{version}/show/#{Path.split(filename)}"
  end

  defp canonical_url(%{assigns: %{live_action: :latest}}, package, _version, filename) do
    url(~p"/preview/#{package}/show/#{Path.split(filename)}")
  end

  defp canonical_url(_socket, package, version, filename) do
    url(~p"/preview/#{package}/#{version}/show/#{Path.split(filename)}")
  end

  defp description(package, version, filename) do
    "View #{filename} from #{package} #{version} on Hex."
  end
end

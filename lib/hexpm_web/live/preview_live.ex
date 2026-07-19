defmodule HexpmWeb.PreviewLive do
  use HexpmWeb, :live_view

  import HexpmWeb.Components.PackageLayout

  alias Hexpm.Preview.Cache
  alias Hexpm.Repository.{Packages, Releases}
  alias HexpmWeb.Components.FileSelector
  alias HexpmWeb.PackageLayoutAssigns

  defmodule NotFoundError do
    defexception message: "Package file not found", plug_status: 404
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       package: nil,
       package_name: params["package"],
       version: nil,
       files: [],
       file_tree: [],
       expanded_paths: MapSet.new(),
       filename: nil,
       filtered_files: [],
       query: "",
       highlighted: nil,
       message: nil,
       raw_url: nil,
       title: "Package files",
       page_title: "Package files | Hex",
       description: nil,
       canonical_url: nil,
       container: "container"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    package_name = params["package"]
    version = params["version"]
    requested_filename = filename(params["filename"])

    with package when not is_nil(package) <- Packages.get("hexpm", package_name),
         [_ | _] = releases <- Releases.all(package),
         release when not is_nil(release) <- find_release(releases, version),
         {:ok, source, replace_path?} <-
           source(package_name, version, requested_filename, params["fallback"]) do
      socket =
        socket
        |> assign_package(package, release, releases)
        |> assign_source(package_name, version, source)

      socket =
        if replace_path? do
          push_patch(socket,
            to: ~p"/packages/#{package_name}/#{version}/files/#{Path.split(source.filename)}",
            replace: true
          )
        else
          socket
        end

      {:noreply, socket}
    else
      _ -> raise NotFoundError
    end
  end

  @impl true
  def handle_event("filter_files", %{"query" => query}, socket) do
    {:noreply,
     assign(socket,
       query: query,
       filtered_files: FileSelector.filter(socket.assigns.files, query)
     )}
  end

  def handle_event("toggle_directory", %{"path" => path}, socket) do
    expanded_paths =
      if MapSet.member?(socket.assigns.expanded_paths, path) do
        MapSet.delete(socket.assigns.expanded_paths, path)
      else
        MapSet.put(socket.assigns.expanded_paths, path)
      end

    {:noreply, assign(socket, expanded_paths: expanded_paths)}
  end

  defp assign_package(socket, package, release, releases) do
    version = to_string(release.version)

    if socket.assigns.package &&
         socket.assigns.package.id == package.id &&
         socket.assigns.version == version do
      socket
    else
      release = Releases.preload(release, [:requirements])

      layout_assigns =
        PackageLayoutAssigns.for_package(socket.assigns.current_user, package,
          releases: releases,
          current_release: release,
          graph_release: release,
          sidebar?: false,
          dependants_count?: false
        )

      socket
      |> assign(layout_assigns)
      |> assign(package: package, package_name: package.name, version: version)
    end
  end

  defp assign_source(socket, package, version, source) do
    {highlighted, message} = render_contents(package, version, source)
    filename = source.filename

    file_tree =
      Cache.fetch({:file_tree, package, version}, fn -> build_file_tree(source.files) end)

    expanded_paths = MapSet.union(socket.assigns.expanded_paths, parent_paths(filename))

    assign(socket,
      files: source.files,
      file_tree: file_tree,
      expanded_paths: expanded_paths,
      filename: filename,
      filtered_files: FileSelector.filter(source.files, ""),
      query: "",
      highlighted: highlighted,
      message: message,
      raw_url: raw_url(package, version, filename),
      title: "#{filename} - #{package} #{version}",
      page_title: "#{filename} - #{package} #{version} | Hex",
      description: description(package, version, filename),
      canonical_url: canonical_url(package, version, filename)
    )
  end

  defp find_release(releases, version) when is_binary(version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp find_release(_releases, _version), do: nil

  defp source(package, version, requested_filename, fallback) do
    opts = if fallback == "default", do: [fallback: :default], else: []

    case Hexpm.Preview.source(package, version, requested_filename, opts) do
      {:ok, source} ->
        {:ok, source, fallback == "default"}

      :error ->
        :error
    end
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
    HexpmWeb.SyntaxHighlight.highlight(
      contents,
      filename,
      "package file #{package} #{version} #{filename}"
    )
  end

  defp filename([_ | _] = parts), do: Path.join(parts)
  defp filename(_filename), do: nil

  defp canonical_url(package, version, filename) do
    url(~p"/packages/#{package}/#{version}/files/#{Path.split(filename)}")
  end

  defp raw_url(package, version, filename) do
    Application.fetch_env!(:hexpm, :cdn_url) <>
      "/preview/" <>
      encode_path(package) <>
      "/" <>
      encode_path(version) <>
      "/" <>
      encode_path(filename)
  end

  defp encode_path(path) do
    URI.encode(path, &(&1 == ?/ or URI.char_unreserved?(&1)))
  end

  defp description(package, version, filename) do
    "View #{filename} from #{package} #{version} on Hex."
  end

  defp build_file_tree(files) do
    files
    |> Enum.reduce(%{}, fn file, tree -> insert_file(tree, Path.split(file), file) end)
    |> tree_nodes("")
  end

  defp parent_paths(filename) do
    filename
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.scan(&Path.join(&2, &1))
    |> MapSet.new()
  end

  defp insert_file(tree, [name], file), do: Map.put(tree, name, {:file, file})

  defp insert_file(tree, [directory | rest], file) do
    Map.update(tree, directory, {:directory, insert_file(%{}, rest, file)}, fn
      {:directory, children} -> {:directory, insert_file(children, rest, file)}
      {:file, _file} -> {:directory, insert_file(%{}, rest, file)}
    end)
  end

  defp tree_nodes(tree, parent) do
    tree
    |> Enum.map(fn
      {name, {:file, file}} ->
        %{type: :file, name: name, path: file}

      {name, {:directory, children}} ->
        path = if parent == "", do: name, else: Path.join(parent, name)
        %{type: :directory, name: name, path: path, children: tree_nodes(children, path)}
    end)
    |> Enum.sort_by(fn node -> {if(node.type == :directory, do: 0, else: 1), node.name} end)
  end

  attr :nodes, :list, required: true
  attr :filename, :string, required: true
  attr :package_name, :string, required: true
  attr :version, :string, required: true
  attr :expanded_paths, :any, required: true
  attr :close_modal?, :boolean, default: false
  attr :modal_id, :string, default: nil

  def source_tree(assigns) do
    ~H"""
    <ul class="space-y-0.5">
      <%= for node <- @nodes do %>
        <li :if={node.type == :directory}>
          <% expanded? = MapSet.member?(@expanded_paths, node.path) %>
          <button
            type="button"
            phx-click="toggle_directory"
            phx-value-path={node.path}
            aria-expanded={expanded?}
            class="flex w-full cursor-pointer items-center gap-1.5 rounded px-2 py-1.5 text-left text-sm font-medium text-grey-700 hover:bg-grey-100 dark:text-grey-200 dark:hover:bg-grey-700/60"
          >
            {icon(:heroicon, "chevron-right",
              class:
                "size-3.5 shrink-0 transition-transform" <>
                  if(expanded?, do: " rotate-90", else: "")
            )}
            {icon(:heroicon, "folder", class: "size-4 shrink-0 text-grey-400")}
            <span class="truncate">{node.name}</span>
          </button>
          <div :if={expanded?} class="ml-3 border-l border-grey-200 pl-2 dark:border-grey-700">
            <.source_tree
              nodes={node.children}
              filename={@filename}
              package_name={@package_name}
              version={@version}
              expanded_paths={@expanded_paths}
              close_modal?={@close_modal?}
              modal_id={@modal_id}
            />
          </div>
        </li>
        <li :if={node.type == :file}>
          <.link
            patch={~p"/packages/#{@package_name}/#{@version}/files/#{Path.split(node.path)}"}
            phx-click={if @close_modal?, do: hide_modal(@modal_id)}
            aria-current={if node.path == @filename, do: "page"}
            class={[
              "flex items-center gap-1.5 rounded px-2 py-1.5 font-mono text-xs transition-colors",
              node.path == @filename &&
                "bg-primary-50 font-semibold text-primary-700 dark:bg-grey-700 dark:text-white",
              node.path != @filename &&
                "text-grey-600 hover:bg-grey-100 hover:text-grey-900 dark:text-grey-300 dark:hover:bg-grey-700/60 dark:hover:text-white"
            ]}
          >
            {icon(:heroicon, "document", class: "ml-5 size-3.5 shrink-0 text-grey-400")}
            <span class="truncate">{node.name}</span>
          </.link>
        </li>
      <% end %>
    </ul>
    """
  end

  attr :files, :list, required: true
  attr :filename, :string, required: true
  attr :package_name, :string, required: true
  attr :version, :string, required: true
  attr :close_modal?, :boolean, default: false
  attr :modal_id, :string, default: nil

  def source_results(assigns) do
    ~H"""
    <HexpmWeb.Components.FileSelector.file_results
      items={@files}
      selected={&(&1 == @filename)}
    >
      <:item :let={result}>
        <.link
          patch={~p"/packages/#{@package_name}/#{@version}/files/#{Path.split(result.item)}"}
          phx-click={if @close_modal?, do: hide_modal(@modal_id)}
          aria-current={if result.item == @filename, do: "page"}
          class={result.class}
        >
          {icon(:heroicon, "document", class: "size-3.5 shrink-0 text-grey-400")}
          <span class="truncate">{result.item}</span>
        </.link>
      </:item>
    </HexpmWeb.Components.FileSelector.file_results>
    """
  end
end

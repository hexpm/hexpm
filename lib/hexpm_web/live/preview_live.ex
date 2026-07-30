defmodule HexpmWeb.PreviewLive do
  use HexpmWeb, :live_view

  import HexpmWeb.Components.PackageLayout

  alias Hexpm.Repository.Releases
  alias HexpmWeb.PackageLayoutAssigns
  alias HexpmWeb.RepositoryAccess

  defmodule NotFoundError do
    defexception message: "Package file not found", plug_status: 404
  end

  # Generated clients keep nearly everything in one directory: ory_client has 384
  # of its 408 files in lib/ory/model, mailslurp 235 of 270. Rendering a whole
  # directory to show one file in it puts those packages back where they started,
  # so a directory renders this many children and the client pages through the
  # rest. The client reads the same number off the DOM.
  @children_limit 100

  def children_limit, do: @children_limit

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       repository: nil,
       package: nil,
       package_name: params["package"],
       version: nil,
       files: [],
       file_tree: [],
       filename: nil,
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
    repository = params["repository"] || "hexpm"
    package_name = params["package"]
    version = params["version"]
    requested_filename = filename(params["filename"])

    with {:ok, package} <-
           RepositoryAccess.fetch_package(socket.assigns.current_user, repository, package_name),
         [_ | _] = releases <- Releases.all(package),
         release when not is_nil(release) <- find_release(releases, version),
         {:ok, source, replace_path?} <-
           source(repository, package_name, version, requested_filename, params["fallback"]) do
      socket =
        socket
        |> assign(repository: repository)
        |> assign_package(package, release, releases)
        |> assign_source(repository, package_name, version, source)

      socket =
        if replace_path? and connected?(socket) do
          push_patch(socket,
            to: files_path(repository, package_name, version, source.filename),
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

  def files_path("hexpm", package, version) do
    ~p"/packages/#{package}/#{version}/files"
  end

  def files_path(repository, package, version) do
    ~p"/packages/#{repository}/#{package}/#{version}/files"
  end

  def files_path("hexpm", package, version, filename) do
    ~p"/packages/#{package}/#{version}/files/#{Path.split(filename)}"
  end

  def files_path(repository, package, version, filename) do
    ~p"/packages/#{repository}/#{package}/#{version}/files/#{Path.split(filename)}"
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

  defp assign_source(socket, repository, package, version, source) do
    {highlighted, message} = render_contents(package, version, source)
    filename = source.filename

    # Opening the path to the file only matters on the render the browser keeps.
    # Once connected the client owns the tree and discards what is pushed to it,
    # so a tree that varies per file would be rebuilt, diffed and sent on every
    # navigation for nothing. Holding it at the top level keeps it identical
    # across navigations, and change tracking then sends none of it.
    open_to = if connected?(socket), do: nil, else: filename

    assign(socket,
      files: source.files,
      file_tree: build_visible_tree(source.files, open_to),
      filename: filename,
      highlighted: highlighted,
      message: message,
      raw_url: raw_url(repository, package, version, filename),
      title: "#{filename} - #{package} #{version}",
      page_title: "#{filename} - #{package} #{version} | Hex",
      description: description(package, version, filename),
      canonical_url: HexpmWeb.Endpoint.url() <> files_path(repository, package, version, filename)
    )
  end

  defp find_release(releases, version) when is_binary(version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp find_release(_releases, _version), do: nil

  defp source(repository, package, version, requested_filename, fallback) do
    case Hexpm.Preview.source(repository, package, version, requested_filename) do
      {:ok, source} ->
        {:ok, source, false}

      :error when fallback == "default" ->
        case Hexpm.Preview.source(repository, package, version) do
          {:ok, source} -> {:ok, source, true}
          :error -> :error
        end

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

  defp raw_url("hexpm", package, version, filename) do
    Application.fetch_env!(:hexpm, :cdn_url) <>
      "/preview/" <>
      encode_path(package) <>
      "/" <>
      encode_path(version) <>
      "/" <>
      encode_path(filename)
  end

  defp raw_url(repository, package, version, filename) do
    ~p"/packages/#{repository}/#{package}/#{version}/raw/#{Path.split(filename)}"
  end

  defp encode_path(path) do
    URI.encode(path, &(&1 == ?/ or URI.char_unreserved?(&1)))
  end

  defp description(package, version, filename) do
    "View #{filename} from #{package} #{version} on Hex."
  end

  # Directories render collapsed, so building the whole tree emits markup nobody
  # sees. Only the top level and the path to the shown file are built; the client
  # has every path and fills a directory in when it is opened.
  defp build_visible_tree(files, filename) do
    child_nodes(files, "", open_directories(filename))
  end

  defp open_directories(nil), do: MapSet.new()

  defp open_directories(filename) do
    filename
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.scan(&Path.join(&2, &1))
    |> MapSet.new()
  end

  defp child_nodes(files, parent, open) do
    depth = if parent == "", do: 0, else: length(Path.split(parent))

    files
    |> Enum.group_by(&Enum.at(Path.split(&1), depth))
    |> Enum.reject(fn {name, _group} -> is_nil(name) end)
    |> Enum.map(fn {name, group} ->
      # A name with anything below it is a directory even if a file shares the
      # name, and a file keeps the path it was stored under rather than one
      # rebuilt from its segments, which need not join back to the same string.
      case Enum.split_with(group, &(length(Path.split(&1)) == depth + 1)) do
        {[file | _], []} ->
          %{type: :file, name: name, path: file}

        {_files, [_ | _] = descendants} ->
          path = if parent == "", do: name, else: Path.join(parent, name)
          open? = MapSet.member?(open, path)
          {children, rest} = open_children(descendants, path, open, open?)

          %{
            type: :directory,
            name: name,
            path: path,
            open?: open?,
            children: children,
            # Only claim the directory is done when every child is on the page.
            # Otherwise the client rebuilds it and takes over paging.
            filled?: open? and rest == []
          }
      end
    end)
    |> Enum.sort_by(fn node -> {if(node.type == :directory, do: 0, else: 1), node.name} end)
  end

  defp open_children(_descendants, _path, _open, false), do: {[], []}

  defp open_children(descendants, path, open, true) do
    descendants
    |> child_nodes(path, open)
    |> Enum.split(@children_limit)
  end

  attr :nodes, :list, required: true
  attr :repository, :string, required: true
  attr :package_name, :string, required: true
  attr :version, :string, required: true

  def source_tree(assigns) do
    ~H"""
    <ul class="space-y-0.5">
      <%= for node <- @nodes do %>
        <li :if={node.type == :directory}>
          <.tree_directory
            path={node.path}
            name={node.name}
            open?={node.open?}
            filled?={node.filled?}
          >
            <.source_tree
              nodes={node.children}
              repository={@repository}
              package_name={@package_name}
              version={@version}
            />
          </.tree_directory>
        </li>
        <li :if={node.type == :file}>
          <.tree_file
            path={node.path}
            name={node.name}
            href={files_path(@repository, @package_name, @version, node.path)}
          />
        </li>
      <% end %>
    </ul>
    """
  end

  attr :path, :string, required: true
  attr :name, :string, required: true
  attr :open?, :boolean, default: false
  attr :filled?, :boolean, default: false
  slot :inner_block

  def tree_directory(assigns) do
    ~H"""
    <details open={@open?} data-dir-path={@path}>
      <summary class="flex w-full cursor-pointer list-none items-center gap-1.5 rounded px-2 py-1.5 text-left text-sm font-medium text-grey-700 hover:bg-grey-100 dark:text-grey-200 dark:hover:bg-grey-700/60 [&::-webkit-details-marker]:hidden">
        {icon(:heroicon, "chevron-right",
          class: "size-3.5 shrink-0 transition-transform [details[open]>summary_&]:rotate-90"
        )}
        {icon(:heroicon, "folder", class: "size-4 shrink-0 text-grey-400")}
        <span data-name class="truncate">{@name}</span>
      </summary>
      <div
        class="ml-3 border-l border-grey-200 pl-2 dark:border-grey-700"
        data-children
        data-filled={@filled? && "true"}
      >
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :path, :string, required: true
  attr :name, :string, required: true
  attr :href, :string, required: true

  def tree_file(assigns) do
    ~H"""
    <a
      href={@href}
      data-phx-link="patch"
      data-phx-link-state="push"
      data-path={@path}
      class="flex items-center gap-1.5 rounded px-2 py-1.5 font-mono text-xs transition-colors text-grey-600 hover:bg-grey-100 hover:text-grey-900 dark:text-grey-300 dark:hover:bg-grey-700/60 dark:hover:text-white aria-[current=page]:bg-primary-50 aria-[current=page]:font-semibold aria-[current=page]:text-primary-700 dark:aria-[current=page]:bg-grey-700 dark:aria-[current=page]:text-white"
    >
      {icon(:heroicon, "document", class: "ml-5 size-3.5 shrink-0 text-grey-400")}
      <span data-name class="truncate">{@name}</span>
    </a>
    """
  end

  attr :files, :list, required: true

  @doc """
  Markup the client clones when it fills a directory, and every path in the
  package so it can build those children and run the file finder without the
  tree being in the document.

  Paths go over already encoded, the same way the router encodes them, so the
  client appends one to the base to get a link and percent-decodes it to get the
  name back. Sending them raw would mean writing the encoding rule a second time
  in JavaScript, and the two spellings disagreed on `!'()*` when it was.
  """
  def tree_templates(assigns) do
    assigns = assign(assigns, :encoded_files, Enum.map(assigns.files, &encode_path/1))

    ~H"""
    <template data-tree-file><.tree_file path="" name="" href="#" /></template>
    <template data-tree-dir><.tree_directory path="" name="" /></template>
    <template data-tree-more><.tree_more /></template>
    <template data-file-paths>{JSON.encode!(@encoded_files)}</template>
    """
  end

  def tree_more(assigns) do
    ~H"""
    <button
      type="button"
      data-tree-more-button
      class="flex w-full items-center gap-1.5 rounded px-2 py-1.5 text-left text-xs font-medium text-primary-700 transition-colors hover:bg-grey-100 dark:text-primary-300 dark:hover:bg-grey-700/60"
    >
      {icon(:heroicon, "chevron-down", class: "ml-5 size-3.5 shrink-0")}
      <span data-name class="truncate"></span>
    </button>
    """
  end
end

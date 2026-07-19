defmodule HexpmWeb.DiffLive do
  use HexpmWeb, :live_view

  require Logger

  import HexpmWeb.Components.PackageLayout

  alias Hexpm.Repository.Releases
  alias HexpmWeb.Components.FileSelector
  alias HexpmWeb.PackageLayoutAssigns
  alias HexpmWeb.Plugs.Attack

  @batch_size 5
  @poll_interval 1_000

  @impl Phoenix.LiveView
  def mount(%{"package" => package, "versions" => versions} = params, session, socket) do
    socket = assign(socket, base_assigns())
    socket = assign(socket, diff_identity: diff_identity(socket, session))
    ignore_whitespace = params["w"] == "1"

    with {:ok, from, to} <- parse_versions(versions),
         {:ok, request} <-
           Hexpm.Diff.prepare(package, from, to, ignore_whitespace: ignore_whitespace) do
      release = Releases.preload(request.to_release, [:requirements])

      layout_assigns =
        PackageLayoutAssigns.for_package(socket.assigns.current_user, request.package_record,
          releases: request.releases,
          current_release: release,
          graph_release: release,
          sidebar?: false,
          dependants_count?: false
        )

      socket =
        socket
        |> assign(layout_assigns)
        |> assign(
          request: request,
          package: request.package,
          from: request.from,
          to: request.to,
          versions: request.versions,
          selected_from: request.from,
          selected_to: request.to,
          ignore_whitespace: ignore_whitespace,
          page_title: "#{request.package} #{request.from}..#{request.to} diff",
          description: "Compare #{request.package} #{request.from} with #{request.to} on Hex.",
          canonical_url:
            canonical_url(request.package, request.from, request.to, ignore_whitespace),
          container: "container"
        )

      load_or_enqueue(socket)
    else
      {:error, reason} -> {:ok, assign(socket, error: error_message(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load-gap", %{"start" => start, "last" => last}, socket) do
    with {:ok, start} <- parse_index(start),
         {:ok, last} <- parse_index(last),
         true <- start >= 0 and start <= last do
      {:noreply, load_gap(socket, start, last)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("load-gap", _params, socket), do: {:noreply, socket}

  def handle_event("filter_files", %{"query" => query}, socket) do
    files = socket.assigns.files

    {:noreply,
     assign(socket,
       query: query,
       filtered_files: filter_diff_files(files, query)
     )}
  end

  def handle_event("select-file", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.files, &(&1.id == id)) do
      socket =
        socket
        |> ensure_piece_loaded(id)
        |> assign(selected_file: id)
        |> push_event("scroll-to-file", %{id: "#{id}-container"})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load-piece", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.all_pieces, &(Hexpm.Diff.piece_id(&1) == id)) do
      {:noreply, load_piece_by_id(socket, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "select-versions",
        %{"versions" => %{"from" => from, "to" => to}},
        socket
      ) do
    {:noreply, assign(socket, selected_from: from, selected_to: to, selector_error: nil)}
  end

  def handle_event("view-diff", %{"versions" => %{"from" => from, "to" => to}}, socket) do
    if from == to do
      {:noreply, assign(socket, selector_error: "Choose two different versions")}
    else
      {:noreply,
       push_navigate(socket,
         to: diff_path(socket.assigns.package, from, to, socket.assigns.ignore_whitespace)
       )}
    end
  end

  def handle_event("retry", _params, socket) do
    case Hexpm.Diff.prepare(
           socket.assigns.package,
           socket.assigns.from,
           socket.assigns.to,
           ignore_whitespace: socket.assigns.ignore_whitespace
         ) do
      {:ok, request} ->
        {:noreply, socket |> assign(request: request) |> throttle_and_enqueue()}

      {:error, reason} ->
        {:noreply, assign(socket, error: error_message(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:poll_job, job_id}, %{assigns: %{job_id: job_id}} = socket) do
    case Hexpm.Diff.job_status(job_id) do
      :missing ->
        {:noreply, assign(socket, job_state: :missing)}

      :completed ->
        case Hexpm.Diff.fetch(socket.assigns.request) do
          {:ok, metadata, pieces} -> {:noreply, show_ready(socket, metadata, pieces)}
          :miss -> {:noreply, assign(socket, job_state: :completed_without_metadata)}
          {:error, reason} -> {:noreply, assign(socket, error: storage_error(reason))}
        end

      state when state in [:discarded, :cancelled] ->
        {:noreply, assign(socket, job_state: state)}

      state ->
        socket = assign(socket, job_state: state)
        schedule_poll(socket)
        {:noreply, socket}
    end
  end

  def handle_info({:poll_job, _stale_job_id}, socket), do: {:noreply, socket}

  defp load_or_enqueue(socket) do
    {:ok, load_or_enqueue_socket(socket)}
  end

  defp load_or_enqueue_socket(socket) do
    case Hexpm.Diff.fetch(socket.assigns.request) do
      {:ok, metadata, pieces} ->
        show_ready(socket, metadata, pieces)

      :miss ->
        enqueue(socket)

      {:error, reason} ->
        assign(socket, error: storage_error(reason))
    end
  end

  defp show_ready(socket, metadata, pieces) do
    files =
      for piece <- pieces,
          file = Hexpm.Diff.piece_file(piece),
          is_binary(file) do
        %{id: Hexpm.Diff.piece_id(piece), path: file}
      end

    piece_order =
      pieces
      |> Enum.with_index()
      |> Map.new(fn {piece, index} -> {Hexpm.Diff.piece_id(piece), index} end)

    socket
    |> assign(
      metadata: metadata,
      all_pieces: pieces,
      piece_order: piece_order,
      remaining_pieces: pieces,
      loaded_pieces: [],
      files: files,
      filtered_files: filter_diff_files(files, ""),
      query: "",
      selected_file: nil,
      job_state: :ready,
      error: nil
    )
    |> load_next_batch()
  end

  defp load_next_batch(%{assigns: %{remaining_pieces: remaining}} = socket) do
    {batch, remaining} = Enum.split(remaining, @batch_size)

    socket
    |> assign(remaining_pieces: remaining)
    |> add_loaded_pieces(batch)
  end

  defp load_gap(socket, start, last) do
    case current_gap_direction(socket, start, last) do
      nil ->
        socket

      direction ->
        pieces =
          socket.assigns.remaining_pieces
          |> Enum.filter(fn piece ->
            index = Map.fetch!(socket.assigns.piece_order, Hexpm.Diff.piece_id(piece))
            index >= start and index <= last
          end)
          |> take_gap_batch(direction)

        socket
        |> assign(
          remaining_pieces:
            Enum.reject(socket.assigns.remaining_pieces, &Enum.member?(pieces, &1))
        )
        |> add_loaded_pieces(pieces)
    end
  end

  defp take_gap_batch(pieces, :backward), do: Enum.take(pieces, -@batch_size)
  defp take_gap_batch(pieces, :forward), do: Enum.take(pieces, @batch_size)

  defp parse_index(index) when is_integer(index), do: {:ok, index}

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {index, ""} -> {:ok, index}
      _ -> :error
    end
  end

  defp parse_index(_index), do: :error

  defp ensure_piece_loaded(%{assigns: %{loaded_pieces: loaded}} = socket, id) do
    if Enum.any?(loaded, &(elem(&1, 0) == id)) do
      socket
    else
      load_piece_by_id(socket, id)
    end
  end

  defp load_piece_by_id(socket, id) do
    case Enum.find(socket.assigns.remaining_pieces, &(Hexpm.Diff.piece_id(&1) == id)) do
      nil ->
        socket

      piece ->
        socket
        |> assign(remaining_pieces: List.delete(socket.assigns.remaining_pieces, piece))
        |> add_loaded_pieces([piece])
    end
  end

  defp add_loaded_pieces(socket, pieces) do
    newly_loaded = Enum.map(pieces, &load_piece/1)

    loaded =
      (socket.assigns.loaded_pieces ++ newly_loaded)
      |> Enum.sort_by(fn {id, _content} -> Map.fetch!(socket.assigns.piece_order, id) end)

    files =
      (socket.assigns.files ++ Enum.flat_map(newly_loaded, &loaded_file/1))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&Map.fetch!(socket.assigns.piece_order, &1.id))

    assign(socket,
      loaded_pieces: loaded,
      files: files,
      filtered_files: filter_diff_files(files, socket.assigns.query)
    )
  end

  defp diff_entries(all_pieces, loaded_pieces, piece_order, selected_file) do
    loaded_pieces = Map.new(loaded_pieces)
    selected_index = Map.get(piece_order, selected_file)

    all_pieces
    |> Enum.chunk_by(&Map.has_key?(loaded_pieces, Hexpm.Diff.piece_id(&1)))
    |> Enum.flat_map(fn pieces ->
      if Map.has_key?(loaded_pieces, pieces |> hd() |> Hexpm.Diff.piece_id()) do
        Enum.map(pieces, fn piece ->
          id = Hexpm.Diff.piece_id(piece)
          {:piece, id, Map.fetch!(loaded_pieces, id)}
        end)
      else
        start = pieces |> hd() |> Hexpm.Diff.piece_id() |> then(&Map.fetch!(piece_order, &1))

        last =
          pieces |> List.last() |> Hexpm.Diff.piece_id() |> then(&Map.fetch!(piece_order, &1))

        direction =
          if is_integer(selected_index) and last < selected_index, do: :backward, else: :forward

        [{:gap, start, last, direction}]
      end
    end)
  end

  defp current_gap_direction(socket, start, last) do
    socket.assigns.all_pieces
    |> diff_entries(
      socket.assigns.loaded_pieces,
      socket.assigns.piece_order,
      socket.assigns.selected_file
    )
    |> Enum.find_value(fn
      {:gap, ^start, ^last, direction} -> direction
      _entry -> nil
    end)
  end

  defp loaded_file({id, {:too_large, file}}), do: [%{id: id, path: file}]

  defp loaded_file({id, {:diff, diff, _highlights}}) do
    [%{id: id, path: diff.to || diff.from || id}]
  end

  defp loaded_file({_id, {:error, _reason}}), do: []

  defp filter_diff_files(files, query) do
    FileSelector.filter_by(files, & &1.path, query)
  end

  defp load_piece(piece) do
    id = Hexpm.Diff.piece_id(piece)

    content =
      with {:ok, stored} <- Hexpm.Diff.fetch_piece(piece),
           {:ok, parsed} <- parse_piece(stored, id) do
        parsed
      else
        {:error, reason} -> {:error, reason}
      end

    {id, content}
  end

  defp parse_piece({:too_large, file}, _id), do: {:ok, {:too_large, file}}

  defp parse_piece({:diff, raw_diff, from_path, to_path}, id) do
    case GitDiff.parse_patch(raw_diff, relative_from: from_path, relative_to: to_path) do
      {:ok, [diff | _]} -> {:ok, {:diff, diff, highlight_diff(diff, id)}}
      {:ok, []} -> {:error, :empty_diff}
      {:error, reason} -> {:error, {:invalid_diff, reason}}
    end
  end

  defp highlight_diff(diff, id) do
    lines = for chunk <- diff.chunks, line <- chunk.lines, do: line
    source = Enum.map(lines, &source_text/1)
    language = diff.to || diff.from

    highlighted =
      HexpmWeb.SyntaxHighlight.highlight_lines(
        source,
        language,
        "package diff #{language}"
      )

    lines
    |> Enum.zip(highlighted)
    |> Map.new(fn {line, html} -> {HexpmWeb.DiffComponent.line_id(id, line), html} end)
  end

  defp source_text(%{text: <<prefix, text::binary>>}) when prefix in [?+, ?-, ?\s], do: text
  defp source_text(%{text: text}), do: text

  defp schedule_poll(socket) do
    if connected?(socket),
      do: Process.send_after(self(), {:poll_job, socket.assigns.job_id}, @poll_interval)

    socket
  end

  defp enqueue(socket) do
    case Hexpm.Diff.pending_job(socket.assigns.request) do
      {:ok, job_id, job_state} ->
        track_job(socket, job_id, job_state)

      :none ->
        throttle_and_enqueue(socket)
    end
  end

  defp throttle_and_enqueue(socket) do
    case Attack.diff_throttle(socket.assigns.diff_identity) do
      {:allow, _data} ->
        case Hexpm.Diff.enqueue(socket.assigns.request) do
          {:ok, job} ->
            track_job(socket, job.id, Hexpm.Diff.job_status(job))

          {:error, :read_only} ->
            assign(socket, error: "Diff generation is unavailable during maintenance.")

          {:error, :overloaded} ->
            assign(socket, error: "The diff generation queue is full. Try again later.")

          {:error, reason} ->
            Logger.error("Could not enqueue diff: #{inspect(reason)}")
            assign(socket, error: "Could not enqueue diff. Try again later.")
        end

      {:block, _data} ->
        assign(socket, error: "Too many diff generation requests. Try again later.")
    end
  end

  defp track_job(socket, job_id, job_state) do
    socket
    |> assign(job_id: job_id, job_state: job_state, error: nil)
    |> schedule_poll()
  end

  defp diff_identity(socket, session) do
    case socket.assigns.current_user do
      %{id: id} -> {:user, id}
      nil -> {:ip, Map.fetch!(session, "remote_ip")}
    end
  end

  defp parse_versions(versions) when is_binary(versions) do
    case String.split(versions, "..", parts: 2) do
      [from, to] when from != "" -> {:ok, from, to}
      _ -> {:error, :invalid_route}
    end
  end

  defp parse_versions(_), do: {:error, :invalid_route}

  defp base_assigns do
    [
      request: nil,
      package: nil,
      from: nil,
      to: nil,
      versions: [],
      selected_from: nil,
      selected_to: nil,
      selector_error: nil,
      diff_identity: nil,
      ignore_whitespace: false,
      metadata: nil,
      all_pieces: [],
      piece_order: %{},
      remaining_pieces: [],
      loaded_pieces: [],
      files: [],
      filtered_files: [],
      query: "",
      selected_file: nil,
      job_id: nil,
      job_state: nil,
      error: nil,
      page_title: "Package diff"
    ]
  end

  defp error_message(:invalid_route), do: "Invalid diff route"
  defp error_message(:invalid_version), do: "Invalid version"
  defp error_message(:package_not_found), do: "Package not found"
  defp error_message(:release_not_found), do: "Release not found"
  defp error_message(:identical_versions), do: "Choose two different versions"
  defp error_message(:no_releases), do: "This package has no releases"
  defp error_message(_), do: "Invalid diff request"

  defp storage_error(reason) do
    Logger.error("Could not load diff cache: #{inspect(reason)}")
    "Could not load diff cache. Try again later."
  end

  def diff_path(package, from, to, ignore_whitespace) do
    query = if ignore_whitespace, do: [w: 1], else: []
    ~p"/diff/#{package}/#{from <> ".." <> to}?#{query}"
  end

  defp canonical_url(package, from, to, ignore_whitespace) do
    url(~p"/diff/#{package}/#{from <> ".." <> to}") <>
      if(ignore_whitespace, do: "?w=1", else: "")
  end

  def job_state_title(:running), do: "Generating diff"
  def job_state_title(:retrying), do: "Retrying diff generation"
  def job_state_title(_), do: "Diff queued"

  def job_state_message(:discarded), do: "Generation failed after all retry attempts."
  def job_state_message(:cancelled), do: "Generation was cancelled."
  def job_state_message(:missing), do: "The generation job could not be found."

  def job_state_message(:completed_without_metadata),
    do: "Generation completed without a readable cache entry."

  attr :files, :list, required: true
  attr :selected_file, :string, default: nil
  attr :close_modal?, :boolean, default: false
  attr :modal_id, :string, default: nil

  def diff_file_results(assigns) do
    ~H"""
    <HexpmWeb.Components.FileSelector.file_results
      items={@files}
      selected={&(&1.id == @selected_file)}
    >
      <:item :let={result}>
        <button
          type="button"
          phx-click={select_file(result.item.id, @close_modal?, @modal_id)}
          aria-current={if result.item.id == @selected_file, do: "true"}
          class={result.class}
        >
          {icon(:heroicon, "document", class: "size-3.5 shrink-0 text-grey-400")}
          <span class="truncate">{result.item.path}</span>
        </button>
      </:item>
    </HexpmWeb.Components.FileSelector.file_results>
    <p
      :if={@files == []}
      class="px-2 py-8 text-center text-sm text-grey-500 dark:text-grey-300"
    >
      No matching files
    </p>
    """
  end

  defp select_file(id, close_modal?, modal_id) do
    js = Phoenix.LiveView.JS.push("select-file", value: %{id: id})
    if close_modal?, do: hide_modal(js, modal_id), else: js
  end
end

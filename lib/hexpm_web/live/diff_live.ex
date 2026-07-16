defmodule HexpmWeb.DiffLive do
  use HexpmWeb, :live_view

  require Logger

  import HexpmWeb.Components.PackageLayout

  alias Hexpm.Repository.Releases
  alias HexpmWeb.PackageLayoutAssigns
  alias HexpmWeb.Plugs.{Attack, Forwarded}

  @batch_size 5
  @poll_interval 1_000

  @impl Phoenix.LiveView
  def mount(%{"package" => package, "versions" => versions} = params, _session, socket) do
    socket = assign(socket, base_assigns())
    socket = assign(socket, diff_identity: diff_identity(socket))
    ignore_whitespace = params["w"] == "1"

    with {:ok, from, to} <- parse_versions(versions),
         {:ok, request} <-
           Hexpm.Diff.prepare(package, from, to, ignore_whitespace: ignore_whitespace) do
      release =
        Releases.preload(request.to_release, [
          :requirements,
          :downloads,
          :publisher,
          :security_advisories
        ])

      layout_assigns =
        PackageLayoutAssigns.for_package(socket.assigns.current_user, request.package_record,
          releases: request.releases,
          current_release: release,
          graph_release: release,
          sidebar?: false
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
  def handle_event("load-more", _params, socket) do
    {:noreply, load_next_batch(socket)}
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
        {:noreply, socket |> assign(request: request) |> load_or_enqueue_socket()}

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
    socket
    |> assign(
      metadata: metadata,
      remaining_pieces: pieces,
      loaded_pieces: [],
      job_state: :ready,
      error: nil
    )
    |> load_next_batch()
  end

  defp load_next_batch(%{assigns: %{remaining_pieces: remaining}} = socket) do
    {batch, remaining} = Enum.split(remaining, @batch_size)
    loaded = Enum.map(batch, &load_piece/1)

    assign(socket,
      loaded_pieces: socket.assigns.loaded_pieces ++ loaded,
      remaining_pieces: remaining
    )
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

  defp diff_identity(socket) do
    case socket.assigns.current_user do
      %{id: id} -> {:user, id}
      nil -> {:ip, remote_ip(socket)}
    end
  end

  defp remote_ip(socket) do
    default =
      case get_connect_info(socket, :peer_data) do
        %{address: address} -> address
        _ -> {0, 0, 0, 0}
      end

    forwarded_for =
      for {"x-forwarded-for", value} <- get_connect_info(socket, :x_headers) || [], do: value

    Forwarded.remote_ip(default, forwarded_for)
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
      remaining_pieces: [],
      loaded_pieces: [],
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
end

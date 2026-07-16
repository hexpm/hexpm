defmodule HexpmWeb.DiffComponent do
  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  alias Phoenix.LiveView.JS

  attr :diff, GitDiff.Patch, required: true
  attr :id, :string, required: true
  attr :highlights, :map, required: true

  def diff(assigns) do
    ~H"""
    <div class="ghd-file">
      <button
        type="button"
        class="ghd-file-header"
        phx-click={JS.toggle_class("hidden", to: "##{@id}-body")}
      >
        <span>
          <span class={["ghd-file-status", "ghd-file-status-#{diff_status(@diff)}"]}>
            {diff_status(@diff)}
          </span>
          {file_header(@diff)}
        </span>
        <svg class="show-hide-diff" viewBox="0 0 10 16" aria-hidden="true">
          <path fill-rule="evenodd" d="M10 10l-1.5 1.5L5 7.75 1.5 11.5 0 10l5-5 5 5z" />
        </svg>
      </button>
      <div class="ghd-diff" id={"#{@id}-body"}>
        <table class="ghd-diff">
          <tbody>
            <%= for chunk <- @diff.chunks do %>
              <tr class="ghd-chunk-header">
                <td class="ghd-line-number">
                  <span>&nbsp;</span><span></span>
                </td>
                <td class="ghd-text"><span class="ghd-text-internal">{chunk.header}</span></td>
              </tr>
              <%= for line <- chunk.lines do %>
                <tr id={line_id(@id, line)} class={["ghd-line", "ghd-line-type-#{line.type}"]}>
                  <td class="ghd-line-number">
                    <span>{line_number(line.from_line_number)}</span>
                    <span>{line_number(line.to_line_number)}</span>
                  </td>
                  <td class="ghd-text">
                    <span class="ghd-text-user">
                      <span class="ghd-line-status">{line_prefix(line.text)}</span>
                      {raw(Map.fetch!(@highlights, line_id(@id, line)))}
                    </span>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :file, :string, required: true

  def too_large(assigns) do
    ~H"""
    <div class="ghd-file">
      <div class="ghd-file-header ghd-file-header-static">
        <span><span class="ghd-file-status">unknown</span>{@file}</span>
      </div>
      <div class="ghd-diff ghd-diff-error">CANNOT RENDER FILES LARGER THAN 1MB</div>
    </div>
    """
  end

  defp file_header(%{from: nil, to: to}), do: to
  defp file_header(%{from: from, to: nil}), do: from
  defp file_header(%{from: path, to: path}), do: path

  defp diff_status(%{from: nil}), do: "added"
  defp diff_status(%{to: nil}), do: "removed"
  defp diff_status(%{from: path, to: path}), do: "changed"

  defp line_number(number), do: to_string(number)

  def line_id(id, line) do
    "#{id}-L#{line_number_id(line.from_line_number)}-#{line_number_id(line.to_line_number)}"
  end

  defp line_number_id(number) when number in [nil, ""], do: "0"
  defp line_number_id(number), do: to_string(number)

  defp line_prefix(<<prefix, _::binary>>) when prefix in [?+, ?-, ?\s], do: <<prefix, ?\s>>
  defp line_prefix(_), do: ""
end

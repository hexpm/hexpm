defmodule HexpmWeb.DiffComponent do
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :diff, GitDiff.Patch, required: true
  attr :id, :string, required: true

  def diff(assigns) do
    assigns = assign(assigns, :lexer, lexer_for(assigns.diff))

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
                <tr id={line_id(@diff, line)} class={["ghd-line", "ghd-line-type-#{line.type}"]}>
                  <td class="ghd-line-number">
                    <span>{line_number(line.from_line_number)}</span>
                    <span>{line_number(line.to_line_number)}</span>
                  </td>
                  <td class="ghd-text">
                    <span class="ghd-text-user highlight">
                      <span class="ghd-line-status">{line_prefix(line.text)}</span>
                      <%= for token <- highlighted_line(line.text, @lexer) do %>
                        <span class={token.class}>{token.text}</span>
                      <% end %>
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

  defp line_id(diff, line) do
    hash = :erlang.phash2({diff.from, diff.to})
    "#{hash}-#{line.from_line_number}-#{line.to_line_number}"
  end

  defp line_prefix(<<prefix, _::binary>>) when prefix in [?+, ?-, ?\s], do: <<prefix, ?\s>>
  defp line_prefix(_), do: ""

  defp highlighted_line(<<prefix, text::binary>>, lexer) when prefix in [?+, ?-, ?\s] do
    highlight(text, lexer)
  end

  defp highlighted_line(text, lexer), do: highlight(text, lexer)

  defp highlight(text, nil), do: [%{class: nil, text: text}]
  defp highlight("", _lexer), do: [%{class: nil, text: ""}]

  defp highlight(text, {lexer, opts}) do
    Enum.map(lexer.lex(text, opts), fn {type, _meta, value} ->
      %{
        class: Makeup.Token.Utils.css_class_for_token_type(type),
        text: IO.iodata_to_binary(value)
      }
    end)
  rescue
    _ -> [%{class: nil, text: text}]
  end

  defp lexer_for(%{from: nil, to: path}), do: lexer_for_path(path)
  defp lexer_for(%{to: nil, from: path}), do: lexer_for_path(path)
  defp lexer_for(%{to: path}), do: lexer_for_path(path)

  defp lexer_for_path(path) do
    filename = Path.basename(path)

    cond do
      filename in ["rebar.config", "rebar.config.script"] ->
        {Makeup.Lexers.ErlangLexer, []}

      String.ends_with?(filename, ".app.src") ->
        {Makeup.Lexers.ErlangLexer, []}

      true ->
        case Path.extname(filename) do
          "." <> extension ->
            case Makeup.Registry.fetch_lexer_by_extension(extension) do
              {:ok, lexer} -> lexer
              :error -> nil
            end

          _ ->
            nil
        end
    end
  end
end

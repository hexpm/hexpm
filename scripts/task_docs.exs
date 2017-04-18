# Run with `mix run scripts/task_docs.exs`
# Generates html for mix task docs, requires the hex client to be installed

defmodule Hexpm.Script.TaskDocs do
  @output_path "lib/hexpm/web/templates/docs/tasks.html.eex"

  @template """
  <%%# This file is auto-generated with 'mix run task_docs.exs' %>

  <h2>Mix tasks</h2>
  <%= for {name, html} <- tasks do %>
  <% id = String.replace(name, ".", "_") %>
    <div class="panel panel-default">
      <div class="panel-heading">
        <h3 class="panel-title">
          <a class="anchor" id="<%= id %>"></a>
          <%= name %>
          <a href="#<%= id %>">
            <%= Phoenix.HTML.safe_to_string Hexpm.Web.ViewIcons.icon(:glyphicon, :link, class: "pull-right") %>
          </a>
        </h3>
      </div>
      <div class="panel-body">
        <%= html %>
      </div>
    </div>
  <% end %>
  """

  def run do
    Mix.Task.load_all
    html = Mix.Task.all_modules
           |> get_docs
           |> Enum.sort(&(elem(&1, 0) < elem(&2, 0)))

    html = EEx.eval_string(@template, [tasks: html])

    File.mkdir_p!(Path.dirname(@output_path))
    File.write!(@output_path, html)
  end

  defp get_docs(tasks) do
    Enum.flat_map(tasks, fn task ->
      name = Mix.Task.task_name(task)
      if String.starts_with?(name, "hex") && Mix.Task.shortdoc(task) do
        {_line, doc} = Code.get_docs(task, :moduledoc)
        if doc, do: [{name, to_html(doc)}]
      end || []
    end)
  end

  defp to_html(doc) do
    Earmark.as_html!(doc)
    |> fix_headings
    |> emphasise_synopsis
  end

  defp fix_headings(html) do
    if String.contains?(html, ["<h1>", "<h6>"]) do
      raise "html heading not allowed (<h1>, <h6>)"
    end

    html
    |> String.replace("<h5>", "<h6>")
    |> String.replace("</h5>", "</h6>")
    |> String.replace("<h4>", "<h5>")
    |> String.replace("</h4>", "</h5>")
    |> String.replace("<h3>", "<h4>")
    |> String.replace("</h3>", "</h4>")
    |> String.replace("<h2>", "<h3>")
    |> String.replace("</h2>", "</h3>")
  end

  defp emphasise_synopsis(html) do
    String.replace(html, ~r"<p>(.*)</p>"U, "<p><em>\\1</em></p>", global: false)
  end
end

Hexpm.Script.TaskDocs.run

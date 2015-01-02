# Run with `mix run task_docs.exs`
# Generates html for mix task docs, requires the hex client to be installed

Mix.Task.load_all
path  = "lib/hex_web/web/templates/docs/tasks.html.eex"
tasks = Mix.Task.all_modules

template = """
<%%# This file is auto-generated with 'mix run task_docs.exs' %>

<h2>Mix tasks</h2>
<%= for {name, html} <- tasks do %>
<% id = String.replace(name, ".", "_") %>
  <div class="panel panel-default">
    <div class="panel-heading">
      <h3 id="<%= id %>" class="panel-title">
        <%= name %>
        <a href="#<%= id %>"><span class="glyphicon glyphicon-link pull-right"></span></a>
      </h3>
    </div>
    <div class="panel-body">
      <%= html %>
    </div>
  </div>
<% end %>
"""

fix_headings = fn html ->
  if String.contains?(html, ["<h1>", "<h5>", "<h6>"]) do
    raise "html heading not allowed (<h1>, <h5>, <h6>)"
  end

  html
  |> String.replace("<h4>", "<h6>")
  |> String.replace("</h4>", "</h6>")
  |> String.replace("<h3>", "<h5>")
  |> String.replace("</h3>", "</h5>")
  |> String.replace("<h2>", "<h4>")
  |> String.replace("</h2>", "</h4>")
end

html_tasks =
  Enum.flat_map(tasks, fn task ->
    name = Mix.Task.task_name(task)
    if String.starts_with?(name, "hex.") do
      {_line, doc} = Code.get_docs(task, :moduledoc)
      html = Earmark.to_html(doc) |> fix_headings.()
      [{name, html}]
    else
      []
    end
  end)

html_tasks = Enum.sort(html_tasks, &(elem(&1, 0) < elem(&2, 0)))

html = EEx.eval_string(template, [tasks: html_tasks])

File.mkdir_p!(Path.dirname(path))
File.write!(path, html)

defmodule HexWeb.Web.Templates do
  require EEx

  def render(page, title \\ nil) do
    template_index(page, title)
  end

  defp inner(page) do
    "#{page}"
  end

  @templates [
    index: [:page, :title] ]

  Enum.each(@templates, fn { name, args } ->
    file = Path.join([__DIR__, "templates", "#{name}.html.eex"])
    EEx.function_from_file(:defp, :"template_#{name}", file, args)
  end)
end

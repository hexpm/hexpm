defmodule HexWeb.Web.Templates do
  require EEx

  def render(page, title \\ nil) do
    template_main(page, title)
  end

  defp inner(page) do
    apply(__MODULE__, :"template_#{page}", [])
  end

  @templates [
    main: [:page, :title],
    index: [] ]

  Enum.each(@templates, fn { name, args } ->
    file = Path.join([__DIR__, "templates", "#{name}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args)
  end)
end

defmodule HexWeb.Email.Templates do
  require EEx

  def safe(value) do
    {:safe, value}
  end

  defmacrop inner do
    quote do
      safe apply(__MODULE__, :"template_#{var!(page)}", [var!(assigns)])
    end
  end

  @templates [
    main: [:page, :assigns],
    confirmation_request: [:assigns],
    confirmed: [:assigns]
  ]

  Enum.each(@templates, fn {name, args} ->
    name = Atom.to_string(name)
    file = Path.join([__DIR__, "templates", "#{path}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args,
                           engine: HexWeb.Web.HTML.Engine)
  end)

  def render(name, assigns) do
    fun = :"template_#{name}"
    apply(__MODULE__, fun, [assigns])
  end

  def render(page, assigns) do
    template_main(page, assigns)
  end
end

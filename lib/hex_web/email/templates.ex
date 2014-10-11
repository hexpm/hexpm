defmodule HexWeb.Email.Templates do
  require EEx

  def safe(value) do
    {:safe, value}
  end

  defmacrop inner do
    quote do
      safe apply(__MODULE__, :"template_#{var!(name)}", [var!(assigns)])
    end
  end

  @templates [
    main: [:name, :assigns],
    confirmation_request: [:assigns],
    confirmed: [:_]
  ]

  Enum.each(@templates, fn {name, args} ->
    name = Atom.to_string(name)
    file = Path.join([__DIR__, "templates", "#{name}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args,
                           engine: HexWeb.Web.HTML.Engine)
  end)

  def render(name, assigns) do
    template_main(name, assigns)
  end
end

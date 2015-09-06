defmodule HexWeb.Web.Templates do
  require EEx
  import HexWeb.Web.HTML.Helpers

  @asset_id :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)

  def render(page, assigns) do
    template_main(page, assigns)
  end

  def safe(value) do
    {:safe, value}
  end

  defmacrop inner do
    quote do
      safe apply(__MODULE__, :"template_#{var!(page)}", [var!(assigns)])
    end
  end

  defp asset_id do
    @asset_id
  end

  @templates [
    main: [:page, :assigns],
    error: [:assigns],
    confirm: [:assigns],
    index: [:assigns],
    packages: [:assigns],
    package: [:assigns],
    docs_usage: [:_],
    docs_publish: [:_],
    docs_tasks: [:_],
    docs_codeofconduct: [:_],
    docs_faq: [:_],
    reset: [:assigns],
    resetresult: [:assigns],
    versions: [:package, :releases, :older?]
  ]

  Enum.each(@templates, fn {name, args} ->
    name = Atom.to_string(name)
    path = String.replace(name, "_", "/")
    file = Path.join([__DIR__, "templates", "#{path}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args,
                           engine: HexWeb.Web.HTML.Engine)
  end)
end

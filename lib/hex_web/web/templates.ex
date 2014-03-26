defmodule HexWeb.Web.Templates do
  require EEx

  @asset_id :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)

  def render(page, assigns, title) do
    template_main(page, assigns, title)
  end

  def safe(value) do
    { :safe, value }
  end

  defmacrop inner do
    quote do
      apply(__MODULE__, :"template_#{var!(page)}", [var!(assigns)])
    end
  end

  defp asset_id do
    @asset_id
  end

  @templates [
    main: [:page, :assigns, :title],
    index: [:assigns] ]

  Enum.each(@templates, fn { name, args } ->
    file = Path.join([__DIR__, "templates", "#{name}.html.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, args,
                           engine: HexWeb.Web.HTMLEngine)
  end)
end

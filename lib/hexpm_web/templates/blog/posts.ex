defmodule HexpmWeb.Blog.Posts do
  @phoenix_root __DIR__

  skip_slugs = ~w()

  all_templates =
    Phoenix.Template.find_all(@phoenix_root)
    |> Enum.map(&Phoenix.View.template_path_to_name(&1, @phoenix_root))
    |> Enum.flat_map(fn
      <<n1, n2, n3, "-", slug::binary>> = template
      when n1 in ?0..?9 and n2 in ?0..?9 and n3 in ?0..?9 ->
        [{Path.rootname(slug), template}]

      _other ->
        []
    end)
    |> Enum.reject(fn {slug, _template} -> slug in skip_slugs end)
    |> Enum.sort_by(&elem(&1, 1), &>=/2)

  def all_templates() do
    unquote(all_templates)
  end
end

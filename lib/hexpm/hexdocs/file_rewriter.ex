defmodule Hexpm.Hexdocs.FileRewriter do
  @link_addition ~s|<a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  @link_hooks [
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" rel="noopener" title="@dignifiedquire">Friedel Ziegelmayer</a>|,
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  ]
  @analytics_addition "<script async defer src=\"https://s.${DOMAIN}/js/script.js\"></script><script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init({endpoint:\"https://s.${DOMAIN}/api/event\"})</script>"
  @official_domains ~w(hex.pm hexdocs.pm hexorgs.pm elixir-lang.org erlang.org)
  @canonical_tag_re ~r{<link[^>]*\brel=["']canonical["'][^>]*>}i
  @hexdocs_link_re ~r{https?://hexdocs\.pm/([a-z][a-z0-9_]*)(?![a-zA-Z0-9_.-])}
  @a_tag_re ~r/<a\s[^>]*href="https?:\/\/[^"]*"[^>]*>/
  @href_re ~r/href="(https?:\/\/[^"]*)"/

  def run(path, content) do
    content
    |> add_elixir_org_link(path)
    |> add_analytics(path)
    |> remove_noindex(path)
    |> rewrite_canonical_links(path)
    |> add_nofollow(path)
  end

  def rewrite_files(dir, files) do
    Enum.each(files, fn path ->
      full_path = Path.join(dir, path)
      File.write!(full_path, run(path, File.read!(full_path)))
    end)
  end

  defp rewrite_canonical_links(content, path) do
    if String.ends_with?(path, ".html") do
      Regex.replace(@canonical_tag_re, content, fn tag ->
        Regex.replace(@hexdocs_link_re, tag, fn _match, package ->
          "https://#{Hexpm.Utils.name_to_subdomain(package)}.hexdocs.pm"
        end)
      end)
    else
      content
    end
  end

  defp add_elixir_org_link(content, path) do
    if String.ends_with?(path, ".html") and not String.contains?(content, @link_addition) do
      String.replace(content, @link_hooks, &(&1 <> " for the " <> @link_addition))
    else
      content
    end
  end

  defp add_analytics(content, path) do
    if String.ends_with?(path, ".html") do
      String.replace(content, "</head>", fn match ->
        host = Application.fetch_env!(:hexpm, :docs_url) |> URI.parse() |> Map.fetch!(:host)
        String.replace(@analytics_addition, "${DOMAIN}", host) <> match
      end)
    else
      content
    end
  end

  defp remove_noindex(content, path) do
    if String.ends_with?(path, ".html") do
      String.replace(content, ~s|<meta name="robots" content="noindex">|, "")
    else
      content
    end
  end

  defp add_nofollow(content, path) do
    if String.ends_with?(path, ".html") do
      Regex.replace(@a_tag_re, content, fn tag ->
        case Regex.run(@href_re, tag) do
          [_, href] -> if official_link?(href), do: tag, else: add_rel_nofollow(tag)
          _other -> tag
        end
      end)
    else
      content
    end
  end

  defp add_rel_nofollow(tag) do
    if tag =~ ~r/\srel="/ do
      Regex.replace(~r/\srel="([^"]*)"/, tag, fn _, existing ->
        rel = if "nofollow" in String.split(existing), do: existing, else: existing <> " nofollow"
        ~s| rel="#{rel}"|
      end)
    else
      String.replace(tag, "<a ", ~s|<a rel="nofollow" |)
    end
  end

  defp official_link?(href) do
    uri = URI.parse(href)

    Enum.any?(
      @official_domains,
      &(uri.host == &1 or (uri.host && String.ends_with?(uri.host, "." <> &1)))
    )
  end
end

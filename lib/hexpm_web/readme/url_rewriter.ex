defmodule HexpmWeb.Readme.URLRewriter do
  @moduledoc """
  Rewrites URLs in README HTML.

  - Resolves relative paths using the preview service (repo.hex.pm/preview/)
  - Rewrites all image URLs to go through the img.hex.pm HMAC-signed proxy
  """

  @doc """
  Rewrites URLs in the given HTML string.

  Relative paths are resolved against the preview service for the given
  package and version.
  """
  def rewrite(html, package_name, version) do
    cdn_url = Application.fetch_env!(:hexpm, :cdn_url)
    base_url = "#{cdn_url}/preview/#{package_name}/#{version}"

    html
    |> Floki.parse_document!()
    |> rewrite_nodes(base_url)
    |> Floki.raw_html()
  end

  defp rewrite_nodes(nodes, base_url) when is_list(nodes) do
    Enum.map(nodes, &rewrite_node(&1, base_url))
  end

  defp rewrite_node({tag, attrs, children}, base_url) do
    attrs = rewrite_attrs(tag, attrs, base_url)
    children = rewrite_nodes(children, base_url)
    {tag, attrs, children}
  end

  defp rewrite_node(other, _base_url), do: other

  @color_scheme_fragments %{
    "gh-light-mode-only" => "color-scheme-light",
    "gh-dark-mode-only" => "color-scheme-dark"
  }

  defp rewrite_attrs("img", attrs, base_url) do
    case List.keytake(attrs, "src", 0) do
      {{"src", src_value}, attrs} ->
        src_value = resolve_url(src_value, base_url)
        {class, src_value} = extract_color_scheme_class(src_value)
        attrs = [{"src", proxy_image_url(src_value)} | attrs]
        if class, do: [{"class", class} | attrs], else: attrs

      nil ->
        attrs
    end
  end

  defp rewrite_attrs("a", attrs, base_url) do
    Enum.map(attrs, fn
      {"href", href} -> {"href", resolve_url(href, base_url)}
      attr -> attr
    end)
  end

  defp rewrite_attrs(_tag, attrs, _base_url), do: attrs

  defp extract_color_scheme_class(url) do
    uri = URI.parse(url)

    case Map.get(@color_scheme_fragments, uri.fragment) do
      nil -> {nil, url}
      class -> {class, %{uri | fragment: nil} |> URI.to_string()}
    end
  end

  defp resolve_url(url, _base_url) when url == "" or is_nil(url), do: url

  defp resolve_url(url, base_url) do
    uri = URI.parse(url)

    cond do
      uri.scheme != nil ->
        url

      String.starts_with?(url, "//") ->
        "https:" <> url

      String.starts_with?(url, "#") ->
        url

      true ->
        path = String.trim_leading(url, "./")

        case Path.safe_relative(path) do
          {:ok, safe_path} -> "#{base_url}/#{safe_path}"
          :error -> url
        end
    end
  end

  @doc """
  Rewrites an image URL to go through the HMAC-signed image proxy.
  """
  def proxy_image_url(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] do
      encoded = Base.encode16(url, case: :lower)
      hmac = compute_hmac(encoded)
      img_url = Application.fetch_env!(:hexpm, :img_url)
      "#{img_url}/fetch/#{hmac}/#{encoded}"
    else
      url
    end
  end

  defp compute_hmac(encoded_url) do
    secret = Application.fetch_env!(:hexpm, :img_proxy_secret)

    :crypto.mac(:hmac, :sha256, secret, encoded_url)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 40)
  end
end

defmodule HexpmWeb.Readme.URLRewriter do
  @moduledoc """
  Rewrites URLs in README HTML.

  - Resolves relative paths using the preview service (repo.hex.pm/preview/)
  - Rewrites all image URLs to go through the img.hex.pm HMAC-signed proxy

  Private packages resolve relative links against the authenticated raw
  endpoint on the main host (session auth works when the user clicks), and
  relative images against a token-signed image endpoint. The image proxy
  fetches images anonymously, so the token — not the session cookie — is what
  authorizes the fetch.
  """

  alias HexpmWeb.ReadmeToken

  @doc """
  Rewrites URLs in a Floki HTML tree.
  """
  def rewrite(tree, "hexpm", package_name, version) do
    cdn_url = Application.fetch_env!(:hexpm, :cdn_url)
    base_url = "#{cdn_url}/preview/#{package_name}/#{version}"
    rewrite_nodes(tree, %{link: base_url, image: base_url, image_token: nil})
  end

  def rewrite(tree, repository, package_name, version) do
    base_url = HexpmWeb.Endpoint.url() <> "/packages/#{repository}/#{package_name}/#{version}"

    rewrite_nodes(tree, %{
      link: "#{base_url}/raw",
      image: "#{base_url}/readme-image",
      image_token: ReadmeToken.sign(repository, package_name, version)
    })
  end

  defp rewrite_nodes(nodes, urls) when is_list(nodes) do
    Enum.map(nodes, &rewrite_node(&1, urls))
  end

  defp rewrite_node({tag, attrs, children}, urls) do
    attrs = rewrite_attrs(tag, attrs, urls)
    children = rewrite_nodes(children, urls)
    {tag, attrs, children}
  end

  defp rewrite_node(other, _urls), do: other

  @color_scheme_fragments %{
    "gh-light-mode-only" => "color-scheme-light",
    "gh-dark-mode-only" => "color-scheme-dark"
  }

  defp rewrite_attrs("img", attrs, urls) do
    case List.keytake(attrs, "src", 0) do
      {{"src", src_value}, attrs} ->
        src_value = resolve_image_url(src_value, urls)
        {class, src_value} = extract_color_scheme_class(src_value)
        attrs = [{"src", proxy_image_url(src_value)} | attrs]
        if class, do: [{"class", class} | attrs], else: attrs

      nil ->
        attrs
    end
  end

  defp rewrite_attrs("a", attrs, urls) do
    Enum.map(attrs, fn
      {"href", href} -> {"href", resolve_url(href, urls.link)}
      attr -> attr
    end)
  end

  defp rewrite_attrs(_tag, attrs, _urls), do: attrs

  defp extract_color_scheme_class(url) do
    uri = URI.parse(url)

    case Map.get(@color_scheme_fragments, uri.fragment) do
      nil -> {nil, url}
      class -> {class, %{uri | fragment: nil} |> URI.to_string()}
    end
  end

  defp resolve_image_url(url, urls) do
    resolved = resolve_url(url, urls.image)

    if urls.image_token && String.starts_with?(resolved, urls.image) do
      resolved <> "?token=" <> urls.image_token
    else
      resolved
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

      url == "#" ->
        url

      Regex.match?(~r/^#fn(ref)?-.+$/, url) ->
        url

      String.starts_with?(url, "#") ->
        "#user-content-" <> String.trim_leading(url, "#")

      true ->
        path =
          url
          |> String.trim_leading("/")
          |> String.trim_leading("./")

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

defmodule HexpmWeb.PreviewImageController do
  use HexpmWeb, :controller

  alias HexpmWeb.ReadmeToken

  @content_types %{
    "png" => "image/png",
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "gif" => "image/gif",
    "svg" => "image/svg+xml",
    "webp" => "image/webp",
    "ico" => "image/x-icon"
  }

  def show(
        conn,
        %{
          "repository" => repository,
          "name" => name,
          "version" => version,
          "filename" => [_ | _] = filename_parts
        } = params
      ) do
    filename = Path.join(filename_parts)

    with :ok <- ReadmeToken.verify(params["token"], repository, name, version),
         content_type when is_binary(content_type) <- content_type(filename),
         {:ok, contents} <- Hexpm.Preview.raw_file(repository, name, version, filename) do
      send_image(conn, content_type, contents)
    else
      _ -> not_found(conn)
    end
  end

  def show(conn, _params) do
    not_found(conn)
  end

  defp content_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      "." <> extension -> Map.get(@content_types, extension)
      _other -> nil
    end
  end

  # Images are token-authorized and fetched anonymously by the image proxy, so
  # unlike the raw endpoint they carry a real image content type. The sandbox
  # CSP keeps a directly-navigated SVG inert in an opaque origin while leaving
  # <img> rendering unaffected.
  defp send_image(conn, content_type, contents) do
    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(200, contents)
  end
end

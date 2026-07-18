defmodule HexpmWeb.PreviewRawController do
  use HexpmWeb, :controller

  alias HexpmWeb.RepositoryAccess

  def show(conn, %{
        "repository" => repository,
        "name" => name,
        "version" => version,
        "filename" => [_ | _] = filename_parts
      }) do
    filename = Path.join(filename_parts)

    with {:ok, package} <-
           RepositoryAccess.fetch_package(conn.assigns.current_user, repository, name),
         release when not is_nil(release) <- find_release(package, version),
         {:ok, contents} <- Hexpm.Preview.raw_file(repository, name, version, filename) do
      send_raw(conn, filename, contents)
    else
      _ -> not_found(conn)
    end
  end

  def show(conn, _params) do
    not_found(conn)
  end

  defp find_release(package, version) do
    package
    |> Releases.all()
    |> Enum.find(&(to_string(&1.version) == version))
  end

  # Raw files are untrusted package contents served from the hex.pm origin,
  # so the content type is never derived from the file and rendering is
  # locked down to keep them inert in the browser.
  defp send_raw(conn, filename, contents) do
    {content_type, disposition} =
      if String.valid?(contents) do
        {"text/plain; charset=utf-8", "inline"}
      else
        {"application/octet-stream", "attachment"}
      end

    basename = filename |> Path.basename() |> String.replace(~r/[^\w.-]/, "_")

    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("content-disposition", ~s(#{disposition}; filename="#{basename}"))
    |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(200, contents)
  end
end

defmodule HexpmWeb.Plugs.PreviewCacheValidation do
  @moduledoc """
  Answers conditional requests for public package file pages.

  Crawlers fetch these pages without a session cookie. A page for a public
  release only changes when the package, its releases or its advisories change,
  or when a new build of hexpm is deployed, so a request without a session
  cookie gets an ETag from those, and a conditional request for an unchanged
  page gets a 304 before the page renders.

  A browser sends the session cookie its first response set, so it always gets
  a rendered page, with CSRF and LiveView tokens that match its session. The
  `Vary: cookie` keeps it from reusing the response it got before it had one.
  """

  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Hexpm.Repo
  alias Hexpm.Repository.{Packages, Release}

  @max_age 86_400

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    with nil <- conn.assigns[:current_user],
         false <- Map.has_key?(conn.req_cookies, HexpmWeb.Endpoint.session_cookie()),
         %{"package" => name, "version" => version} = params <- conn.path_params,
         "hexpm" <- Map.get(params, "repository", "hexpm"),
         git_sha when is_binary(git_sha) <- Application.get_env(:hexpm, :git_sha),
         etag when is_binary(etag) <- etag(git_sha, name, version) do
      if etag_matches?(conn, etag) do
        conn
        |> put_validator_headers(etag)
        |> send_resp(304, "")
        |> halt()
      else
        register_before_send(conn, fn
          %Plug.Conn{status: 200} = conn -> put_validator_headers(conn, etag)
          conn -> conn
        end)
      end
    else
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp etag(git_sha, name, version) do
    with %{} = package <- Packages.get("hexpm", name),
         releases = releases(package),
         %{id: release_id} <- Enum.find(releases, &(to_string(&1.version) == version)) do
      vulnerable? = Repo.exists?(Release.vulnerable_ids([release_id]))
      advisories = Enum.map(package.security_advisories, &{&1.id, &1.updated_at})

      digest =
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary(
            {git_sha, package.id, package.updated_at, releases, release_id, vulnerable?,
             advisories}
          )
        )

      ~s(W/"#{Base.url_encode64(digest, padding: false)}")
    end
  end

  defp releases(package) do
    from(r in Release,
      where: r.package_id == ^package.id,
      order_by: r.id,
      select: %{id: r.id, version: r.version, updated_at: r.updated_at}
    )
    |> Repo.all()
  end

  defp etag_matches?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.any?(&(&1 in [etag, "*"]))
  end

  defp put_validator_headers(conn, etag) do
    conn
    |> put_resp_header("etag", etag)
    |> put_resp_header("cache-control", "private, max-age=#{@max_age}")
    |> put_resp_header("vary", Enum.join(get_resp_header(conn, "vary") ++ ["cookie"], ", "))
  end
end

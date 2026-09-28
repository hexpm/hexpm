defmodule HexpmWeb.ShortURLControllerTest do
  use HexpmWeb.ConnCase, async: true
  alias Hexpm.ShortURLs.Target

  test "redirects to the target" do
    url = "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1"
    target = Hexpm.Repo.insert!(%Target{url: url, url_hash: Target.url_hash(url)})

    insert(:short_url, short_code: "AaBbC", target_id: target.id)

    conn = get(build_conn(), "/l/AaBbC")
    assert redirected_to(conn, 301) == url
  end

  test "redirects a short code without a target to its url" do
    Hexpm.Repo.insert_all("short_urls", [
      %{
        short_code: "GgHhJ",
        url: "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1",
        inserted_at: NaiveDateTime.utc_now()
      }
    ])

    conn = get(build_conn(), "/l/GgHhJ")
    assert redirected_to(conn, 301) == "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1"
  end

  test "show an invalid short code" do
    conn = get(build_conn(), "/l/f4k3")
    assert response(conn, 404)
  end

  # Rows predating the host validation, or written by anything but the
  # changeset, are checked again on the way out rather than redirected to.
  test "does not redirect to a stored URL that fails validation" do
    url = "https://evil.example\\@hex.pm/"
    target = Hexpm.Repo.insert!(%Target{url: url, url_hash: Target.url_hash(url)})
    insert(:short_url, short_code: "DdEeF", target_id: target.id)
    conn = get(build_conn(), "/l/DdEeF")
    assert response(conn, 404)
  end
end

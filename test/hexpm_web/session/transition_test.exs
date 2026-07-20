defmodule HexpmWeb.Session.TransitionTest do
  use HexpmWeb.ConnCase, async: false

  alias Hexpm.{PlugSession, Repo}

  test "anonymous page views do not write session rows" do
    conn = get(build_conn(), "/")

    assert conn.status == 200
    assert Repo.aggregate(PlugSession, :count) == 0
    assert %{value: _} = conn.resp_cookies["_hexpm_key"]
  end

  test "legacy database session is read and rewritten as a cookie session" do
    session =
      Repo.insert!(%PlugSession{token: :crypto.strong_rand_bytes(32), data: %{"foo" => "bar"}})

    legacy_cookie = "#{session.id}++#{Base.url_encode64(session.token)}"

    conn =
      build_conn()
      |> put_req_cookie("_hexpm_key", legacy_cookie)
      |> get("/")

    assert get_session(conn, "foo") == "bar"
    refute get_session(conn, HexpmWeb.Session.Transition.legacy_marker())

    assert %{value: new_cookie} = conn.resp_cookies["_hexpm_key"]
    refute new_cookie == legacy_cookie

    Repo.delete!(session)

    conn =
      build_conn()
      |> put_req_cookie("_hexpm_key", new_cookie)
      |> get("/")

    assert get_session(conn, "foo") == "bar"
  end

  test "invalid cookies start a fresh session" do
    conn =
      build_conn()
      |> put_req_cookie("_hexpm_key", "42++notvalidbase64")
      |> get("/")

    assert conn.status == 200
    refute get_session(conn, "foo")
  end
end

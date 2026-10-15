defmodule HexpmWeb.EndpointLogTest do
  use HexpmWeb.ConnCase

  test "logs one line per request with its fields" do
    assert [{:info, line}] = capture_log_lines(fn -> get(build_conn(), "/diffs") end)

    assert %{
             message: "HTTP request",
             event: "http.request",
             method: "GET",
             path: "/diffs",
             status: 200,
             duration_us: duration,
             controller: "HexpmWeb.DiffController",
             action: :index,
             format: "html",
             request_id: request_id
           } = line

    assert is_integer(duration)
    assert is_binary(request_id)
    refute Map.has_key?(line, :credential)
  end

  test "logs the id of the API key that authenticated the request" do
    user = insert(:user)
    secret = key_for(user)
    key = Hexpm.Repo.get_by!(Hexpm.Accounts.Key, user_id: user.id)

    line =
      request_line(fn ->
        build_conn()
        |> put_req_header("authorization", secret)
        |> get("/api/users/me")
      end)

    assert %{path: "/api/users/me", status: 200, credential: credential} = line
    assert credential == "key:#{key.id}"
    refute inspect(line) =~ secret
  end

  test "logs the jti of the OAuth token that authenticated the request" do
    user = insert(:user)
    client = insert(:oauth_client)
    session = insert(:oauth_session, user: user, client_id: client.client_id)

    {:ok, token} =
      Hexpm.OAuth.Tokens.create_and_insert_for_user(
        user,
        client.client_id,
        ["api"],
        "authorization_code",
        "test_grant_ref-#{System.unique_integer([:positive])}",
        user_session_id: session.id
      )

    line =
      request_line(fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.access_token}")
        |> get("/api/users/me")
      end)

    assert %{path: "/api/users/me", status: 200, credential: credential} = line
    assert credential == "token:#{token.jti}"
    refute inspect(line) =~ token.access_token
  end

  test "logs the id of the browser session that made the request" do
    user = insert(:user)
    conn = test_login(build_conn(), user)
    session = Hexpm.Repo.get_by!(Hexpm.UserSession, user_id: user.id, type: "browser")

    line = request_line(fn -> get(conn, "/dashboard/security") end)

    assert %{path: "/dashboard/security", status: 200, credential: credential} = line
    assert credential == "session:#{session.id}"
  end

  test "logs a response that is not a success with its status" do
    assert [{:info, line}] = capture_log_lines(fn -> get(build_conn(), "/api/no/such/route") end)
    assert %{event: "http.request", path: "/api/no/such/route", status: 404} = line
  end

  test "logs the 500 for a request whose process exits" do
    assert [{:info, line}] =
             capture_log_lines(fn ->
               assert_error_sent(500, fn -> get(build_conn(), "/_test/exit") end)
             end)

    assert %{event: "http.request", path: "/_test/exit", status: 500} = line
  end

  defp request_line(fun) do
    lines = for {:info, %{event: "http.request"} = line} <- capture_log_lines(fun), do: line
    assert [line] = lines
    line
  end
end

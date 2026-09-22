defmodule Hexpm.SecurityLogTest do
  use ExUnit.Case, async: true

  import Hexpm.TestHelpers, only: [capture_log_lines: 1]
  import Plug.Conn
  import Plug.Test

  alias Hexpm.Accounts.Key
  alias Hexpm.SecurityLog

  setup do
    conn =
      conn(:post, "/login")
      |> Map.put(:remote_ip, {192, 0, 2, 10})
      |> put_req_header("user-agent", "curl/8.0")

    %{conn: conn}
  end

  test "describes the request and the credential", %{conn: conn} do
    Logger.metadata(request_id: "req-1")

    assert [{:warning, line}] =
             capture_log_lines(fn ->
               SecurityLog.auth_failure(conn, :password, :wrong_password, username: "eric")
             end)

    assert line == %{
             message: "Authentication failed",
             event: "auth.failure",
             method: "password",
             reason: "wrong_password",
             path: "/login",
             ip: "192.0.2.10",
             user_agent: "curl/8.0",
             request_id: "req-1",
             username: "eric"
           }
  end

  test "expands a key into its ids and drops what is absent", %{conn: conn} do
    key = %Key{id: 7, user_id: 3, organization_id: nil}
    conn = delete_req_header(conn, "user-agent")

    assert [{:warning, line}] =
             capture_log_lines(fn ->
               SecurityLog.auth_failure(conn, :api_key, :revoked, key: key)
             end)

    assert %{key_id: 7, user_id: 3} = line
    refute Map.has_key?(line, :organization_id)
    refute Map.has_key?(line, :user_agent)
    refute Map.has_key?(line, :request_id)
  end

  test "makes text safe to encode", %{conn: conn} do
    conn = put_req_header(conn, "user-agent", <<"bad ", 0xFF, " agent">>)

    assert [{:warning, line}] =
             capture_log_lines(fn ->
               SecurityLog.auth_failure(conn, :password, :unknown_user,
                 username: "a" <> String.duplicate("́", 2000)
               )
             end)

    assert line.user_agent == "bad � agent"
    assert byte_size(line.username) == 1023
    assert String.length(line.username) == 1
    assert JSON.encode!(line)
  end
end

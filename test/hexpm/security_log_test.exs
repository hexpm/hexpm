defmodule Hexpm.SecurityLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
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
    SecurityLog.auth_failure(conn, :password, :wrong_password, username: "eric")

    assert_received {SecurityLog, event}

    assert %{
             event: "auth.failure",
             severity: "WARNING",
             message: "Failed password authentication: wrong_password",
             method: "password",
             reason: "wrong_password",
             path: "/login",
             ip: "192.0.2.10",
             user_agent: "curl/8.0",
             request_id: "req-1",
             username: "eric"
           } = event

    assert {:ok, _, _} = DateTime.from_iso8601(event.time)
  end

  test "expands a key into its ids and drops what is absent", %{conn: conn} do
    key = %Key{id: 7, user_id: 3, organization_id: nil}
    SecurityLog.auth_failure(delete_req_header(conn, "user-agent"), :api_key, :revoked, key: key)

    assert_received {SecurityLog, event}
    assert %{key_id: 7, user_id: 3} = event
    refute Map.has_key?(event, :organization_id)
    refute Map.has_key?(event, :user_agent)
    refute Map.has_key?(event, :request_id)
  end

  test "makes text safe to encode", %{conn: conn} do
    conn = put_req_header(conn, "user-agent", <<"bad ", 0xFF, " agent">>)

    SecurityLog.auth_failure(conn, :password, :unknown_user,
      username: "a" <> String.duplicate("\u0301", 2000)
    )

    assert_received {SecurityLog, event}
    assert event.user_agent == "bad � agent"
    assert byte_size(event.username) == 1023
    assert String.length(event.username) == 1
    assert String.valid?(event.username)
    assert Jason.encode!(event)
  end

  test "writes one JSON line to standard output", %{conn: conn} do
    Application.put_env(:hexpm, SecurityLog, sink: :stdio)
    on_exit(fn -> Application.put_env(:hexpm, SecurityLog, sink: :process) end)

    output = capture_io(fn -> SecurityLog.auth_failure(conn, :tfa, :invalid_code, user_id: 3) end)

    assert String.ends_with?(output, "\n")
    [line] = String.split(output, "\n", trim: true)

    assert %{
             "event" => "auth.failure",
             "method" => "tfa",
             "reason" => "invalid_code",
             "user_id" => 3,
             "ip" => "192.0.2.10"
           } = Jason.decode!(line)
  end
end

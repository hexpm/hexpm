defmodule HexpmWeb.BanditTelemetryTest do
  use ExUnit.Case, async: true

  import Hexpm.TestHelpers, only: [start_bandit: 1]

  alias HexpmWeb.BanditTelemetry

  defmodule App do
    @behaviour Plug

    import Plug.Conn

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(%Plug.Conn{path_info: ["ok"]} = conn, _opts), do: send_resp(conn, 200, "ok")

    def call(%Plug.Conn{path_info: ["redirect"]} = conn, _opts) do
      conn |> put_resp_header("location", "/ok") |> send_resp(302, "")
    end

    def call(%Plug.Conn{path_info: ["not_sent"]} = conn, _opts), do: conn
    def call(%Plug.Conn{path_info: ["bad_request"]}, _opts), do: raise(Plug.BadRequestError)
    def call(%Plug.Conn{path_info: ["raise"]}, _opts), do: raise("plug raised")
  end

  defmodule Other do
    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, _opts), do: Plug.Conn.send_resp(conn, 200, "ok")
  end

  setup do
    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:hexpm, :http, :response],
        [:bandit, :request, :exception]
      ])

    on_exit(fn -> :telemetry.detach(ref) end)

    :ok = BanditTelemetry.attach(App)
    on_exit(fn -> :telemetry.detach({BanditTelemetry, App}) end)

    %{ref: ref, url: "http://localhost:#{start_bandit(App)}"}
  end

  defp get(url), do: Req.get!(url, retry: false, redirect: false)

  @tag :capture_log
  test "reports the 500 Bandit sends for a plug that sent no response", %{ref: ref, url: url} do
    assert %Req.Response{status: 500} = get(url <> "/not_sent")

    assert_receive {[:bandit, :request, :exception], ^ref, _,
                    %{plug: {App, _}, exception: %Plug.Conn.NotSentError{}}}

    assert_receive {[:hexpm, :http, :response], ^ref, %{count: 1}, %{status_class: "5xx"}}
  end

  @tag :capture_log
  test "reports the 500 Bandit sends for a plug that raised", %{ref: ref, url: url} do
    assert %Req.Response{status: 500} = get(url <> "/raise")
    assert_receive {[:hexpm, :http, :response], ^ref, %{count: 1}, %{status_class: "5xx"}}
  end

  test "reports an exception's own status", %{ref: ref, url: url} do
    assert %Req.Response{status: 400} = get(url <> "/bad_request")
    assert_receive {[:hexpm, :http, :response], ^ref, %{count: 1}, %{status_class: "4xx"}}
  end

  test "reports the responses the plug sent by status class", %{ref: ref, url: url} do
    assert %Req.Response{status: 200} = get(url <> "/ok")
    assert_receive {[:hexpm, :http, :response], ^ref, %{count: 1}, %{status_class: "2xx"}}

    assert %Req.Response{status: 302} = get(url <> "/redirect")
    assert_receive {[:hexpm, :http, :response], ^ref, %{count: 1}, %{status_class: "3xx"}}
  end

  test "reports the endpoint's responses from the time the application starts" do
    for event <- [[:bandit, :request, :stop], [:bandit, :request, :exception]] do
      ids = event |> :telemetry.list_handlers() |> Enum.map(& &1.id)
      assert {BanditTelemetry, HexpmWeb.Endpoint} in ids
    end
  end

  test "leaves out the responses Bandit sends for other plugs", %{ref: ref} do
    assert %Req.Response{status: 200} = get("http://localhost:#{start_bandit(Other)}/")
    refute_receive {[:hexpm, :http, :response], ^ref, _, _}
  end
end

defmodule HexpmWeb.BanditTelemetry do
  @moduledoc """
  Reports every response Bandit sends for the endpoint, by status class, on
  `[:hexpm, :http, :response]`, which `hexpm.http.response.total` counts.

  Phoenix's request metrics come from `Plug.Telemetry`'s `before_send`, which
  never runs for the 500 Bandit sends itself when a plug raises before
  sending a response or returns without sending one
  (`Plug.Conn.NotSentError`). Bandit ends each request with
  `[:bandit, :request, :stop]`, whose conn carries the status it sent, or
  with `[:bandit, :request, :exception]`, after which it sends the
  exception's status unless the plug already sent a response; Phoenix
  renders an exception with that same status before it re-raises. A request
  Bandit refuses while reading it, or whose connection closed, ends with
  `:stop` and an `:error` but no status and isn't reported.
  """

  @events [[:bandit, :request, :stop], [:bandit, :request, :exception]]

  @doc """
  Reports the responses Bandit sends for `plug`. The metrics server's Bandit
  serves `PromEx.Plug` and isn't counted.
  """
  def attach(plug \\ HexpmWeb.Endpoint) do
    :telemetry.attach_many({__MODULE__, plug}, @events, &__MODULE__.handle_event/4, plug)
  end

  @doc false
  def handle_event([:bandit, :request, :stop], _measurements, metadata, plug) do
    case metadata do
      %{plug: {^plug, _opts}, conn: %Plug.Conn{status: status}} when is_integer(status) ->
        report(status)

      _metadata ->
        :ok
    end
  end

  def handle_event([:bandit, :request, :exception], _measurements, metadata, plug) do
    case metadata do
      %{plug: {^plug, _opts}, exception: exception} ->
        exception |> Plug.Exception.status() |> Plug.Conn.Status.code() |> report()

      _metadata ->
        :ok
    end
  end

  defp report(status) do
    :telemetry.execute([:hexpm, :http, :response], %{count: 1}, %{
      status_class: "#{div(status, 100)}xx"
    })
  end
end

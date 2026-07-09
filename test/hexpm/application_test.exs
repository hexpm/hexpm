defmodule Hexpm.ApplicationTest do
  use ExUnit.Case, async: true

  describe "sentry_before_send/1" do
    test "drops websocket frame deserialization crash reports" do
      event =
        Sentry.Event.create_event(
          message: "GenServer #PID<0.123.0> terminating",
          extra: %{crash_reason: ~s({:deserializing, "Received unsupported RSV flags 2"})}
        )

      assert Hexpm.Application.sentry_before_send(event) == nil
    end

    test "keeps other crash reports" do
      event =
        Sentry.Event.create_event(
          message: "GenServer #PID<0.123.0> terminating",
          extra: %{crash_reason: "{:badmatch, :error}"}
        )

      assert Hexpm.Application.sentry_before_send(event) == event
    end

    test "keeps events without a crash reason" do
      event = Sentry.Event.create_event(exception: %RuntimeError{message: "oops"})

      assert Hexpm.Application.sentry_before_send(event) == event
    end

    test "drops exceptions with a status below 500" do
      event =
        Sentry.Event.create_event(
          exception: %Phoenix.Router.NoRouteError{message: "no route", plug_status: 404}
        )

      assert Hexpm.Application.sentry_before_send(event) == nil
    end
  end
end

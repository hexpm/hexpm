defmodule Hexpm.ApplicationTest do
  use ExUnit.Case, async: true

  alias Hexpm.Application

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

    test "keeps unexpected read-only write exceptions" do
      event = Sentry.Event.create_event(exception: %Hexpm.WriteInReadOnlyMode{})

      assert Hexpm.Application.sentry_before_send(event) == event
    end
  end

  describe "mode supervision" do
    test "web and worker select distinct role children and all is their union" do
      web_ids = child_ids(Application.children(:web))
      worker_ids = child_ids(Application.children(:worker))
      all_ids = child_ids(Application.children(:all))

      assert HexpmWeb.Endpoint in web_ids
      assert Oban in web_ids
      assert Oban in worker_ids
      assert Hexpm.Hexdocs.Queue in worker_ids
      assert Hexpm.Hexdocs.Debouncer in worker_ids
      assert Hexpm.Preview.Queue in worker_ids
      refute HexpmWeb.Endpoint in worker_ids
      refute Hexpm.Hexdocs.Queue in web_ids
      refute Hexpm.Preview.Queue in web_ids
      assert MapSet.union(web_ids, worker_ids) == all_ids

      worker_children = child_ids_in_order(Application.children(:worker))

      assert child_index(worker_children, Hexpm.Hexdocs.Debouncer) <
               child_index(worker_children, Oban)

      assert child_index(worker_children, Oban) <
               child_index(worker_children, Hexpm.Hexdocs.Queue)
    end

    test "production defaults to web and validates explicit modes" do
      assert Application.mode(:prod, nil) == :web
      assert Application.mode(:prod, "web") == :web
      assert Application.mode(:prod, "worker") == :worker

      assert_raise ArgumentError, ~r/invalid HEXPM_MODE/, fn ->
        Application.mode(:prod, "invalid")
      end
    end

    test "development and test always run all children" do
      assert Application.mode(:dev, "worker") == :all
      assert Application.mode(:test, "web") == :all
    end

    test "read-only mode keeps web reads available and quiesces write workers" do
      children = Application.children(:all, false)
      ids = child_ids(children)

      assert HexpmWeb.Endpoint in ids
      refute :task_setup in ids
      refute Oban in ids
      refute Hexpm.Hexdocs.Queue in ids
      refute Hexpm.Hexdocs.Debouncer in ids
      refute Hexpm.Preview.Queue in ids
    end
  end

  defp child_ids(children) do
    MapSet.new(children, fn child -> Supervisor.child_spec(child, []).id end)
  end

  defp child_ids_in_order(children) do
    Enum.map(children, fn child -> Supervisor.child_spec(child, []).id end)
  end

  defp child_index(children, child), do: Enum.find_index(children, &(&1 == child))
end

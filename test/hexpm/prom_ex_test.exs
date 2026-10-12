defmodule Hexpm.PromExTest do
  use ExUnit.Case, async: false

  defp oban_plugin() do
    Enum.find(Hexpm.PromEx.plugins(), fn
      {Hexpm.PromEx.Plugins.Oban, _opts} -> true
      _plugin -> false
    end)
  end

  defp put_queues(queues) do
    Application.put_env(
      :hexpm,
      Oban,
      Keyword.put(Application.fetch_env!(:hexpm, Oban), :queues, queues)
    )
  end

  setup do
    config = Application.fetch_env!(:hexpm, Oban)
    on_exit(fn -> Application.put_env(:hexpm, Oban, config) end)
    :ok
  end

  test "reports Oban metrics only on nodes that run queues" do
    put_queues(false)
    refute oban_plugin()

    put_queues([])
    refute oban_plugin()

    put_queues(registry: 1)
    assert {Hexpm.PromEx.Plugins.Oban, poll_rate: 60_000} = oban_plugin()
  end

  defp plugin_modules() do
    Enum.map(Hexpm.PromEx.plugins(), fn
      {module, _opts} -> module
      module -> module
    end)
  end

  test "reports Phoenix metrics through the plugin that relabels them" do
    assert Hexpm.PromEx.Plugins.Phoenix in plugin_modules()
    refute PromEx.Plugins.Phoenix in plugin_modules()
  end

  test "reports Ecto metrics through the plugin that rebuckets them" do
    assert Hexpm.PromEx.Plugins.Ecto in plugin_modules()
    refute PromEx.Plugins.Ecto in plugin_modules()
  end

  # initialize_counters/0 reaches every handler on the events it seeds, so
  # these tests run apart from the async tests that attach to them.
  describe "initialize_counters/0" do
    test "starts the bounded counters at zero" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:hexpm, :repository, :publish],
          [:hexpm, :organization_deletions, :run],
          [:hexpm, :workload_identity, :mint, :success],
          [:hexpm, :api, :authenticate],
          [:hexpm, :registry_builder, :build, :done],
          [:hexpm, :registry_builder, :build, :exception],
          [:hexpm, :sentry, :filtered],
          [:hexpm, :cdn, :verify, :stop],
          [:hexpm, :cdn, :purge, :done],
          [:hexpm, :cdn, :purge, :absorb],
          [:db_connection, :connection_error],
          [:db_connection, :connected],
          [:hexpm, :email, :deliver, :done],
          [:hexpm, :email, :deliver, :raised]
        ])

      on_exit(fn -> :telemetry.detach(ref) end)

      assert Hexpm.PromEx.initialize_counters() == :ignore

      assert_received {[:hexpm, :repository, :publish], ^ref, %{count: 0}, %{}}

      assert_received {[:hexpm, :organization_deletions, :run], ^ref,
                       %{
                         cleared: 0,
                         scheduled: 0,
                         reminded: 0,
                         deleted: 0,
                         skipped: 0,
                         failed: 0
                       }, %{}}

      assert_received {[:hexpm, :workload_identity, :mint, :success], ^ref, %{count: 0},
                       %{provider: "github"}}

      assert_received {[:hexpm, :api, :authenticate], ^ref, %{count: 0},
                       %{scheme: :key, result: :revoked_key}}

      assert_received {[:hexpm, :registry_builder, :build, :done], ^ref, %{count: 0},
                       %{type: :repository, result: :ok}}

      assert_received {[:hexpm, :registry_builder, :build, :exception], ^ref, %{count: 0},
                       %{type: :package_delete}}

      assert_received {[:hexpm, :sentry, :filtered], ^ref, %{count: 0}, %{class: :pool_timeout}}

      assert_received {[:hexpm, :cdn, :verify, :stop], ^ref, %{count: 0},
                       %{pop: :nearest, result: :stale}}

      assert_received {[:hexpm, :cdn, :verify, :stop], ^ref, %{count: 0},
                       %{pop: "nrt-tokyo-jp", result: :error}}

      assert_received {[:hexpm, :cdn, :purge, :done], ^ref, %{count: 0},
                       %{service: :fastly_hexdocs, result: :ok, rounds: 3}}

      assert_received {[:hexpm, :cdn, :purge, :done], ^ref, %{count: 0},
                       %{service: :fastly_hexrepo, result: :error, rounds: 0}}

      assert_received {[:hexpm, :cdn, :purge, :absorb], ^ref, %{count: 0},
                       %{service: :fastly_hexdocs_private}}

      assert_received {[:db_connection, :connection_error], ^ref, %{count: 0},
                       %{error: %DBConnection.ConnectionError{reason: :queue_timeout}}}

      assert_received {[:db_connection, :connected], ^ref, %{count: 0}, %{}}

      assert_received {[:hexpm, :email, :deliver, :done], ^ref, %{count: 0},
                       %{type: "verification", outcome: "error"}}

      assert_received {[:hexpm, :email, :deliver, :raised], ^ref, %{count: 0},
                       %{type: "package_published"}}

      assert Hexpm.PromEx.Plugins.Hexpm.count(%{count: 0}) == 0
      assert Hexpm.PromEx.Plugins.Hexpm.count(%{duration: 10}) == 1
    end

    test "creates the series the first event increments and no histogram observation" do
      metrics =
        for plugin <- [Hexpm.PromEx.Plugins.Hexpm, Hexpm.PromEx.Plugins.Email],
            event <- List.wrap(plugin.event_metrics(otp_app: :hexpm)),
            metric <- event.metrics,
            do: metric

      start_supervised!(PromEx.Storage.Core.child_spec(__MODULE__.Metrics, metrics))

      Hexpm.PromEx.initialize_counters()
      samples = samples(__MODULE__.Metrics)

      assert ~s(hexpm_registry_builder_build_total{result="ok",type="repository"} 0) in samples

      assert ~s(hexpm_cdn_purge_total{result="error",rounds="0",service="fastly_hexrepo"} 0) in samples

      assert ~s(hexpm_cdn_purge_absorbed_total{service="fastly_hexrepo"} 0) in samples

      for type <- Hexpm.Emails.types() do
        for outcome <- ["ok", "error"] do
          assert ~s(hexpm_prom_ex_email_deliver_total{outcome="#{outcome}",type="#{type}"} 0) in samples
        end

        assert ~s(hexpm_prom_ex_email_deliver_exception_total{type="#{type}"} 0) in samples
      end

      assert Enum.all?(samples, &String.ends_with?(&1, " 0"))
      refute Enum.any?(samples, &String.contains?(&1, "_milliseconds"))

      Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Basic not-base64")
      |> HexpmWeb.AuthHelpers.authenticate_at(~U[2026-09-30 23:59:59Z])

      series = ~s(hexpm_api_authenticate_total{result="invalid",scheme="basic"})

      assert Enum.filter(samples(__MODULE__.Metrics), &String.starts_with?(&1, series)) ==
               [series <> " 1"]
    end
  end

  defp samples(name) do
    name
    |> PromEx.Storage.Core.scrape()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
  end
end

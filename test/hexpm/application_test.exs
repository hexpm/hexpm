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
  end

  describe "mode supervision" do
    test "web and worker select distinct role children and all is their union" do
      web_ids = child_ids(Application.children(:web))
      worker_ids = child_ids(Application.children(:worker))
      all_ids = child_ids(Application.children(:all))

      assert HexpmWeb.Endpoint in web_ids
      assert Oban not in web_ids
      assert Oban in worker_ids
      assert Hexpm.Hexdocs.Queue in worker_ids
      assert Hexpm.Hexdocs.Debouncer in worker_ids
      assert Hexpm.Preview.Queue in worker_ids
      refute HexpmWeb.Endpoint in worker_ids
      refute Hexpm.Hexdocs.Queue in web_ids
      refute Hexpm.Preview.Queue in web_ids
      assert MapSet.union(web_ids, worker_ids) == all_ids
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

    test "worker runtime configuration requires only shared and worker settings" do
      elixir = System.find_executable("elixir")
      erl = System.find_executable("erl")
      path = [Path.dirname(elixir), Path.dirname(erl), "/usr/bin", "/bin"] |> Enum.uniq()

      env = [
        "PATH=#{Enum.join(path, ":")}",
        "HEXPM_MODE=worker",
        "HEXPM_SIGNING_KEY=key",
        "HEXPM_REPO_BUCKET=repo",
        "HEXPM_LOGS_BUCKET=logs",
        "HEXPM_DOCS_BUCKET=docs",
        "HEXPM_PREVIEW_BUCKET=preview",
        "HEXPM_PREVIEW_URL=https://preview.hex.pm",
        "HEXPM_CDN_URL=cdn",
        "HEXPM_DOCS_URL=https://hexdocs.pm",
        "HEXPM_PRIVATE_DOCS_URL=https://hexorgs.pm",
        "HEXPM_FASTLY_KEY=fastly-key",
        "HEXPM_FASTLY_HEXREPO=fastly-service",
        "HEXPM_BILLING_KEY=billing-key",
        "HEXPM_BILLING_URL=billing-url",
        "HEXPM_AWS_ACCESS_KEY_ID=aws-key",
        "HEXPM_AWS_ACCESS_KEY_SECRET=aws-secret",
        "HEXPM_SENTRY_DSN=sentry-dsn",
        "HEXPM_ENV=prod",
        "HEXPM_DOCS_PRIVATE_BUCKET=private-docs",
        "HEXPM_DOCS_QUEUE_ID=queue",
        "HEXPM_PREVIEW_QUEUE_ID=preview-queue",
        "HEXPM_DOCS_TYPESENSE_URL=https://typesense.example",
        "HEXPM_DOCS_TYPESENSE_API_KEY=typesense-key",
        "HEXPM_DOCS_TYPESENSE_COLLECTION=hexdocs",
        "HEXPM_DOCS_GITHUB_USER=hexpm",
        "HEXPM_DOCS_GITHUB_TOKEN=github-token",
        "HEXPM_FASTLY_DOCS_KEY=docs-fastly-key",
        "HEXPM_FASTLY_DOCS=public-docs-service",
        "HEXPM_FASTLY_PRIVATE_DOCS=private-docs-service"
      ]

      expression =
        ~S|Config.Reader.read!("config/runtime.exs", env: :prod); IO.write("configured")|

      assert {"configured", 0} =
               System.cmd(
                 System.find_executable("env"),
                 ["-i" | env] ++ [elixir, "-e", expression]
               )
    end
  end

  defp child_ids(children) do
    MapSet.new(children, fn child -> Supervisor.child_spec(child, []).id end)
  end
end

defmodule Hexpm.Emails.TelemetryTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureLog

  alias Hexpm.Emails
  alias Hexpm.Emails.{Mailer, Outbox, OutboxWorker}

  defmodule RaisingAdapter do
    use Swoosh.Adapter

    @impl Swoosh.Adapter
    def deliver(_email, _config), do: raise("provider unreachable")
  end

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    mailer_config = Application.fetch_env!(:hexpm, Emails.Mailer)

    on_exit(fn ->
      Logger.configure(level: level)
      Application.put_env(:hexpm, Emails.Mailer, mailer_config)
    end)

    %{mailer_config: mailer_config}
  end

  test "logs one line per accepted delivery with the type and message id", context do
    put_adapter(context, Emails.ProviderIdAdapter, message_id: "sg-message-id")

    log = capture_log(fn -> Mailer.deliver!(announcement()) end)

    assert [line] = String.split(log, "\n", trim: true)

    assert line =~
             ~r"^\[info\] \[email\] type=announcement outcome=ok message_id=sg-message-id duration=\d+ms$"
  end

  test "logs a refused delivery with the provider's answer", context do
    put_adapter(context, Emails.FailingAdapter, [])

    log =
      capture_log(fn ->
        assert {:error, :mail_unavailable} = Mailer.deliver(announcement())
      end)

    assert log =~
             ~r"^\[warning\] \[email\] type=announcement outcome=error error=:mail_unavailable duration=\d+ms$"m
  end

  test "logs a delivery that raised", context do
    put_adapter(context, RaisingAdapter, [])

    log =
      capture_log(fn ->
        assert_raise RuntimeError, "provider unreachable", fn ->
          Mailer.deliver!(announcement())
        end
      end)

    assert log =~
             ~r"^\[warning\] \[email\] type=announcement outcome=exception kind=error reason=%RuntimeError\{message: \"provider unreachable\"\} duration=\d+ms$"m
  end

  test "an outbox delivery names its entry and category" do
    entry = Outbox.enqueue!(announcement(), category: "admin.announcement")

    log =
      capture_log(fn ->
        assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
      end)

    assert log =~
             ~r"\[email\] type=announcement outcome=ok outbox_entry_id=#{entry.id} category=admin.announcement duration=\d+ms$"m
  end

  defp announcement do
    Emails.announcement("bob@example.com", "Hex.pm - Service update", "Body")
  end

  defp put_adapter(context, adapter, extra) do
    config =
      context.mailer_config
      |> Keyword.put(:adapter, adapter)
      |> Keyword.merge(extra)

    Application.put_env(:hexpm, Emails.Mailer, config)
  end
end

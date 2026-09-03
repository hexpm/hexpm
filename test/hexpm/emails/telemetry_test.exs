defmodule Hexpm.Emails.TelemetryTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Emails
  alias Hexpm.Emails.{Mailer, Outbox, OutboxWorker}

  defmodule RaisingAdapter do
    use Swoosh.Adapter

    @impl Swoosh.Adapter
    def deliver(_email, _config), do: raise("provider unreachable")
  end

  setup do
    mailer_config = Application.fetch_env!(:hexpm, Emails.Mailer)
    on_exit(fn -> Application.put_env(:hexpm, Emails.Mailer, mailer_config) end)
    %{mailer_config: mailer_config}
  end

  test "logs one line per accepted delivery with the type and message id", context do
    put_adapter(context, Emails.ProviderIdAdapter, message_id: "sg-message-id")

    assert [line] = email_lines(fn -> Mailer.deliver!(announcement()) end)

    assert %{
             "severity" => "INFO",
             "message" => "Email delivery",
             "event" => "email.delivery",
             "type" => "announcement",
             "outcome" => "ok",
             "message_id" => "sg-message-id",
             "duration_us" => duration
           } = line

    assert is_integer(duration)
    refute Map.has_key?(line, "error")
  end

  test "logs a refused delivery with the provider's answer", context do
    put_adapter(context, Emails.FailingAdapter, [])

    assert [line] =
             email_lines(fn ->
               assert {:error, :mail_unavailable} = Mailer.deliver(announcement())
             end)

    assert %{
             "severity" => "WARNING",
             "message" => "Email delivery",
             "type" => "announcement",
             "outcome" => "error",
             "error" => ":mail_unavailable"
           } = line
  end

  test "logs a delivery that raised", context do
    put_adapter(context, RaisingAdapter, [])

    assert [line] =
             email_lines(fn ->
               assert_raise RuntimeError, "provider unreachable", fn ->
                 Mailer.deliver!(announcement())
               end
             end)

    assert %{
             "severity" => "WARNING",
             "message" => "Email delivery",
             "outcome" => "exception",
             "kind" => "error",
             "reason" => "%RuntimeError{message: \"provider unreachable\"}"
           } = line
  end

  test "an outbox delivery names its entry and category" do
    entry = Outbox.enqueue!(announcement(), category: "admin.announcement")

    assert [line] =
             email_lines(fn ->
               assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
             end)

    assert %{
             "outcome" => "ok",
             "outbox_entry_id" => entry_id,
             "outbox_category" => "admin.announcement"
           } = line

    assert entry_id == entry.id
  end

  defp email_lines(fun) do
    fun
    |> capture_json_log()
    |> Enum.filter(&(&1["event"] == "email.delivery"))
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

defmodule Hexpm.SlackTest do
  use ExUnit.Case, async: false
  import Mox

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:hexpm, :slack_webhook_url)
    on_exit(fn -> Application.put_env(:hexpm, :slack_webhook_url, original) end)
    :ok
  end

  test "posts the text to the webhook as JSON" do
    Application.put_env(:hexpm, :slack_webhook_url, "https://hooks.slack.test/T/B/x")

    expect(Hexpm.HTTP.Mock, :post, fn url, headers, body ->
      assert url == "https://hooks.slack.test/T/B/x"
      assert {"content-type", "application/json"} in headers
      assert body == %{text: "hello"}
      {:ok, 200, [], "ok"}
    end)

    assert :ok = Hexpm.Slack.post("hello")
  end

  test "drops the message without a webhook" do
    Application.put_env(:hexpm, :slack_webhook_url, nil)
    assert :ok = Hexpm.Slack.post("hello")
  end

  test "reports a refused message" do
    Application.put_env(:hexpm, :slack_webhook_url, "https://hooks.slack.test/T/B/x")
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body -> {:ok, 404, [], "no_service"} end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:status, 404}} = Hexpm.Slack.post("hello")
      end)

    assert log =~ "Slack webhook failed"
  end
end

defmodule Hexpm.Slack do
  @moduledoc """
  Posts a message to the operations channel through an incoming webhook.
  Without a webhook configured the message is logged and dropped.
  """

  require Logger

  def post(text) when is_binary(text) do
    case Application.get_env(:hexpm, :slack_webhook_url) do
      nil ->
        Logger.debug(%{message: "Slack message dropped, no webhook configured", text: text})
        :ok

      url ->
        headers = [{"content-type", "application/json"}]

        result =
          Hexpm.HTTP.retry(
            fn -> Hexpm.HTTP.impl().post(url, headers, %{text: text}) end,
            "slack",
            statuses: [429, 500..599]
          )

        case result do
          {:ok, 200, _headers, _body} ->
            :ok

          {:ok, status, _headers, body} ->
            Logger.error(%{message: "Slack webhook failed", status: status, body: body})
            {:error, {:status, status}}

          {:error, reason} ->
            Logger.error(%{message: "Slack webhook failed", reason: inspect(reason)})
            {:error, reason}
        end
    end
  end
end

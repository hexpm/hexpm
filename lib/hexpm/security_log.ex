defmodule Hexpm.SecurityLog do
  @moduledoc """
  Security events, logged as warnings with the event's fields in the message.

  Production writes every log line as JSON, so the fields land in the
  `jsonPayload` of `hexpm-prod.logs.stdout`, where the `logs.auth_failures`
  view selects the authentication failures.
  """

  import Plug.Conn, only: [get_req_header: 2]
  require Logger

  alias Hexpm.Accounts.Key

  @max_text_bytes 1024

  @doc """
  Records an authentication attempt that failed.

  `method` is the credential that was checked (`:password`, `:tfa`,
  `:recovery_code`, `:totp`, `:api_key`, `:oauth_token` or `:refresh_token`)
  and `reason` why it was refused. `fields` say what the credential was for:
  `:username` as it was typed, the `:user_id` of an account, or the `:key`
  that resolved.
  """
  def auth_failure(%Plug.Conn{} = conn, method, reason, fields \\ []) do
    event =
      [
        message: "Authentication failed",
        event: "auth.failure",
        method: to_string(method),
        reason: to_string(reason),
        path: conn.request_path,
        ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
        user_agent: conn |> get_req_header("user-agent") |> List.first()
      ]
      |> Kernel.++(Enum.flat_map(fields, &expand/1))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {key, text(value)} end)

    Logger.warning(event)
  end

  defp expand({:key, %Key{} = key}),
    do: [key_id: key.id, user_id: key.user_id, organization_id: key.organization_id]

  defp expand(field), do: [field]

  defp text(value) when is_binary(value) do
    value
    |> String.replace_invalid()
    |> truncate(@max_text_bytes)
  end

  defp text(value), do: value

  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: string |> binary_part(0, max) |> String.replace_invalid("")
end

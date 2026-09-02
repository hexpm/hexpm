defmodule Hexpm.SecurityLog do
  @moduledoc """
  Security events, one JSON line each on standard output.

  The container log agent parses each line into `jsonPayload` and the
  `big-query` log sink stores it in `hexpm-prod.logs.stdout`, where the
  `logs.auth_failures` view selects the authentication failures.
  """

  import Plug.Conn, only: [get_req_header: 2]

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
    %{
      event: "auth.failure",
      severity: "WARNING",
      message: "Failed #{method} authentication: #{reason}",
      method: to_string(method),
      reason: to_string(reason),
      path: conn.request_path,
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first(),
      request_id: Logger.metadata()[:request_id]
    }
    |> Map.merge(Map.new(Enum.flat_map(fields, &expand/1)))
    |> emit()
  end

  defp expand({:key, %Key{} = key}),
    do: [key_id: key.id, user_id: key.user_id, organization_id: key.organization_id]

  defp expand(field), do: [field]

  defp emit(event) do
    event =
      event
      |> Map.put(:time, DateTime.to_iso8601(DateTime.utc_now()))
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {key, text(value)} end)

    case Application.fetch_env!(:hexpm, __MODULE__)[:sink] do
      :stdio -> IO.binwrite(:standard_io, [Jason.encode_to_iodata!(event), ?\n])
      :process -> send(self(), {__MODULE__, event})
    end
  end

  defp text(value) when is_binary(value) do
    value
    |> String.replace_invalid()
    |> truncate(@max_text_bytes)
  end

  defp text(value), do: value

  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: string |> binary_part(0, max) |> String.replace_invalid("")
end

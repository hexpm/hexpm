defmodule HexWeb.Plug do
  import Plug.Connection

  defexception BadRequest, [:message] do
    defimpl Plug.Exception do
      def status(_exception) do
        400
      end
    end
  end

  defmacro assign_pun(conn, vars) do
    Enum.reduce(vars, conn, fn { field, _, _ } = var, ast ->
      quote do
        Plug.Connection.assign(unquote(ast), unquote(field), unquote(var))
      end
    end)
  end

  @doc """
  Read the body from a Plug connection.

  Should be in Plug proper eventually and can be removed at that point.
  """
  def read_body(Plug.Conn[adapter: { adapter, state }] = conn, limit) do
    case read_body({ :ok, "", state }, "", limit, adapter) do
      { :too_large, state } ->
        { :too_large, conn.adapter({ adapter, state }) }
      { :ok, body, state } ->
        { :ok, body, conn.adapter({ adapter, state }) }
    end
  end

  def read_body!(Plug.Conn[adapter: { adapter, state }] = conn, limit) do
    case read_body({ :ok, "", state }, "", limit, adapter) do
      { :too_large, _state } ->
        raise Plug.Parsers.RequestTooLargeError
      { :ok, body, state } ->
        { body, conn.adapter({ adapter, state }) }
    end
  end

  defp read_body({ :ok, buffer, state }, acc, limit, adapter) when limit >= 0,
    do: read_body(adapter.stream_req_body(state, 1_000_000), acc <> buffer, limit - byte_size(buffer), adapter)
  defp read_body({ :ok, _, state }, _acc, _limit, _adapter),
    do: { :too_large, state }

  defp read_body({ :done, state }, acc, limit, _adapter) when limit >= 0,
    do: { :ok, acc, state }
  defp read_body({ :done, state }, _acc, _limit, _adapter),
    do: { :too_large, state }
end

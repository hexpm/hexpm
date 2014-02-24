defmodule HexWeb.Plugs.Exception do
  @behaviour Plug.Wrapper

  import Plug.Connection

  def init(opts), do: opts

  def wrap(conn, _opts, fun) do
    try do
      fun.(conn)
    catch
      :error, error ->
        stacktrace = System.stacktrace
        exception = Exception.normalize(error)
        status = Plug.Exception.status(error)

        if status == 500, do: print_error(:error, exception, stacktrace)
        send_resp(conn, status, "")
      kind, error ->
        print_error(kind, error, System.stacktrace)
        send_resp(conn, 500, "")
    end
  end

  defp print_error(:error, exception, stacktrace) do
    IO.puts "** (#{inspect exception.__record__(:name)}) #{exception.message}"
    IO.puts Exception.format_stacktrace(stacktrace)
  end

  defp print_error(kind, reason, stacktrace) do
    IO.puts "** (#{kind}) #{inspect(reason)}"
    IO.puts Exception.format_stacktrace(stacktrace)
  end
end

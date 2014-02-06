defmodule ExplexWeb.Router do
  use Plug.Router
  import Plug.Connection

  def call(conn, _opts) do
    try do
      dispatch(conn.method, conn.path_info, conn)
    catch
      kind, error ->
        print_error(kind, error, System.stacktrace)
        if impl = Plug.Exception.impl_for(error) do
          { :halt, send_resp(conn, impl.status(error), "") }
        else
          { :halt, send_resp(conn, 500, "") }
        end
    end
  end

  defp print_error(:error, exception, stacktrace) do
    IO.inspect ""
    exception = Exception.normalize(exception)
    IO.puts IO.ANSI.escape_fragment("\n%{red}** (#{inspect exception.__record__(:name)}) #{exception.message}", true)
    IO.puts IEx.Evaluator.format_stacktrace(stacktrace)
  end

  defp print_error(kind, reason, stacktrace) do
    IO.puts IO.ANSI.escape_fragment("\n%{red}** (#{kind}) #{inspect(reason)}", true)
    IO.puts IEx.Evaluator.format_stacktrace(stacktrace)
  end

  match _ do
    { :halt, send_resp(conn, 404, "") }
  end
  match _ do
    { :ok, send_resp(conn, 404, "") }
  end
end

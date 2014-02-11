defmodule ExplexWeb.Util.ExceptionPlug do
  @behaviour Plug.Wrapper

  import Plug.Connection

  def init(opts), do: opts

  def wrap(conn, _opts, fun) do
    try do
      fun.(conn)
    catch
      kind, error ->
        if IEx.started?, do: print_error(kind, error, System.stacktrace)

        if impl = Plug.Exception.impl_for(error) do
          send_resp(conn, impl.status(error), "")
        else
          send_resp(conn, 500, "")
        end
    end
  end

  defp print_error(:error, exception, stacktrace) do
    exception = Exception.normalize(exception)
    IO.puts IO.ANSI.escape_fragment("\n%{red}** (#{inspect exception.__record__(:name)}) #{exception.message}", true)
    IO.puts IEx.Evaluator.format_stacktrace(stacktrace)
  end

  defp print_error(kind, reason, stacktrace) do
    IO.puts IO.ANSI.escape_fragment("\n%{red}** (#{kind}) #{inspect(reason)}", true)
    IO.puts IEx.Evaluator.format_stacktrace(stacktrace)
  end
end

defmodule HexWeb.Web.HTML.Engine do
  alias HexWeb.Web.HTML
  use EEx.Engine

  def handle_body(buffer) do
    unsafe(buffer)
  end

  def handle_text(buffer, text) do
    quote do
      {:safe, unquote(unsafe(buffer)) <> unquote(text)}
    end
  end

  def handle_expr(buffer, "=", expr) do
    expr   = expr(expr)
    buffer = unsafe(buffer)

    {:safe, quote do
      tmp = unquote(buffer)
      tmp <> (case unquote(expr) do
        {:safe, bin} when is_binary(bin) -> bin
        bin when is_binary(bin) -> HTML.escape(bin)
        other -> HTML.Safe.to_string(other)
      end)
    end}
  end

  def handle_expr(buffer, "", expr) do
    expr   = expr(expr)
    buffer = unsafe(buffer)

    quote do
      tmp = unquote(buffer)
      unquote(expr)
      tmp
    end
  end

  defp unsafe({:safe, value}), do: value
  defp unsafe(value), do: value

  defp expr(expr) do
    Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
  end
end

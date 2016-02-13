defmodule HexWeb.SharedHelpers do
  def if_value(arg, nil, _fun),   do: arg
  def if_value(arg, false, _fun), do: arg
  def if_value(arg, _true, fun),  do: fun.(arg)
end

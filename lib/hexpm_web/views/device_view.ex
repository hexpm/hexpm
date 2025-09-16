defmodule HexpmWeb.DeviceView do
  use HexpmWeb, :view

  @doc """
  Formats a user code for display by inserting a hyphen in the middle.
  Converts "ABCD1234" to "ABCD-1234" for better readability.
  """
  def format_user_code(nil), do: ""
  def format_user_code(""), do: ""

  def format_user_code(user_code) when byte_size(user_code) == 8 do
    String.slice(user_code, 0, 4) <> "-" <> String.slice(user_code, 4, 4)
  end

  def format_user_code(user_code), do: user_code

  @doc """
  Normalizes user input by removing dashes and converting to uppercase.
  This allows users to enter codes with or without formatting.
  """
  def normalize_user_code(nil), do: ""
  def normalize_user_code(""), do: ""

  def normalize_user_code(user_code) when is_binary(user_code) do
    user_code
    |> String.replace("-", "")
    |> String.upcase()
  end
end

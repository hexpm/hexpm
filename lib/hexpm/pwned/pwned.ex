defmodule Hexpm.Pwned do
  @moduledoc """
  This module acts as an interface to the haveibeenpwned API
  https://haveibeenpwned.com/API/v2
  """

  @callback password_breached?(String.t()) :: boolean()

  defp impl(), do: Application.get_env(:hexpm, :pwned_impl)

  def password_breached?(password), do: impl().password_breached?(password)
end

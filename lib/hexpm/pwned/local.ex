defmodule Hexpm.Pwned.Local do
  @behaviour Hexpm.Pwned

  @spec password_breached?(String.t()) :: boolean
  def password_breached?("password"), do: true
  def password_breached?(_), do: false
end

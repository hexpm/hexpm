defmodule Hexpm.Pwned.Local do
  @behaviour Hexpm.Pwned

  @impl Hexpm.Pwned
  def password_breached?(_password), do: false
end

defmodule HexpmWeb.API.WebAuthView do
  use HexpmWeb, :view

  def render("code." <> _, reponse) do
    Map.take(reponse, [:device_code, :user_code])
  end

  def render("access." <> _, %{write_key: write_key, read_key: read_key}) do
    %{
      write_key: write_key.user_secret,
      read_key: read_key.user_secret
    }
  end
end

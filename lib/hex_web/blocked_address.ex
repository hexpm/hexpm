defmodule HexWeb.BlockedAddress do
  use HexWeb.Web, :model

  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end
end

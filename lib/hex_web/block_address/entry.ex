defmodule HexWeb.BlockedAddress do
  use HexWeb.Web, :schema

  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end
end

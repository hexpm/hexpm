defmodule HexWeb.BlockAddress.Entry do
  use HexWeb.Web, :schema

  # TODO: rename to block_address_entries
  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end
end

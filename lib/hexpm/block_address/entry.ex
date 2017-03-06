defmodule Hexpm.BlockAddress.Entry do
  use Hexpm.Web, :schema

  # TODO: rename to block_address_entries
  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end
end

defmodule Hexpm.BlockAddress.Entry do
  use Hexpm.Schema

  # TODO: rename to block_address_entries
  schema "blocked_addresses" do
    field :ip, :string
    field :comment, :string
  end
end

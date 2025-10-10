defmodule Hexpm.PlugSession do
  use Hexpm.Schema

  @timestamps_opts [type: :naive_datetime]

  schema "sessions" do
    field :token, :binary
    field :data, :map

    timestamps()
  end
end

defmodule Hexpm.RateLimit do
  use Hexpm.Schema

  @primary_key {:key, :string, autogenerate: false}

  schema "rate_limits" do
    field :count, :integer
    field :expires_at, :utc_datetime_usec
  end
end

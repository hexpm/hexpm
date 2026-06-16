defmodule Hexpm.Accounts.ReservedUsername do
  use Hexpm.Schema

  schema "reserved_usernames" do
    field :name, :string

    timestamps(updated_at: false)
  end

  def by_name(name) do
    from(r in __MODULE__, where: fragment("lower(?)", r.name) == ^String.downcase(name))
  end
end

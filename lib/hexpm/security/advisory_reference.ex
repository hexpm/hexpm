defmodule Hexpm.Security.AdvisoryReference do
  use Hexpm.Schema

  schema "security_advisory_references" do
    field :advisory_id, :string
    field :type, :string
    field :url, :string
  end

  def changeset(reference, params) do
    reference
    |> cast(params, ~w(type url)a)
    |> validate_required(~w(type url)a)
    |> validate_length(:url, max: 2000)
  end
end

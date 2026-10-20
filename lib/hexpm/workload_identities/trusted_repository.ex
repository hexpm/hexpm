defmodule Hexpm.WorkloadIdentities.TrustedRepository do
  @moduledoc """
  A repository whose workflows a workload identity trusts, named as
  `owner/name` and pinned by its immutable ID, so a repository deleted and
  created again under the same name isn't trusted.
  """

  use Hexpm.Schema

  @primary_key false
  embedded_schema do
    field :name, :string
    field :id, :string
  end

  @doc """
  The repository's name without its owner, as the forms take it.
  """
  def short_name(%__MODULE__{name: name}), do: name |> String.split("/") |> List.last()
end

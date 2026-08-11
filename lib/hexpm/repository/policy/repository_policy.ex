defmodule Hexpm.Repository.Policy.RepositoryPolicy do
  @moduledoc """
  One tab of a policy: the configuration that applies to releases from a single
  repository (in practice `hexpm` and the organization's own repository).

  A tab holds an optional restriction — a baseline cooldown, advisory severity
  threshold, and retirement reasons applied to every release in the repository
  — and a list of package-scoped overrides.
  """
  use Hexpm.Schema

  alias Hexpm.Repository.Cooldown
  alias Hexpm.Repository.Policy
  alias Hexpm.Repository.Policy.Override

  embedded_schema do
    field :repository, :string
    field :cooldown, :string
    field :advisory_min_severity, :integer
    field :retirement_reasons, {:array, :integer}, default: []

    embeds_many :overrides, Override, on_replace: :delete
  end

  def changeset(repository_policy, attrs) do
    changeset =
      cast(repository_policy, attrs, [
        :repository,
        :cooldown,
        :advisory_min_severity,
        :retirement_reasons
      ])

    repository = get_field(changeset, :repository)

    changeset
    |> cast_embed(:overrides, with: &Override.changeset(&1, &2, repository))
    |> validate_required([:repository])
    |> validate_number(:advisory_min_severity,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 4
    )
    |> validate_retirement_reasons()
    |> validate_cooldown()
    |> validate_unique_final_override_packages()
  end

  defp validate_retirement_reasons(changeset) do
    case get_change(changeset, :retirement_reasons) do
      nil ->
        changeset

      reasons when is_list(reasons) ->
        valid = Policy.retirement_reasons()

        if Enum.all?(reasons, &Map.has_key?(valid, &1)) do
          changeset
        else
          add_error(changeset, :retirement_reasons, "contains invalid reasons")
        end
    end
  end

  defp validate_cooldown(changeset) do
    case get_change(changeset, :cooldown) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :cooldown, nil)

      cooldown ->
        case Cooldown.duration_to_seconds(cooldown) do
          {:ok, _seconds} -> changeset
          :error -> add_error(changeset, :cooldown, "is invalid")
        end
    end
  end

  defp validate_unique_final_override_packages(changeset) do
    packages =
      changeset
      |> get_field(:overrides, [])
      |> Enum.filter(&(Map.get(&1, :action) in [:allow, :deny]))
      |> Enum.map(&Map.get(&1, :package))
      |> Enum.reject(&is_nil/1)

    if length(packages) == length(Enum.uniq(packages)) do
      changeset
    else
      add_error(changeset, :overrides, "include only one Allow or Deny override per package")
    end
  end
end

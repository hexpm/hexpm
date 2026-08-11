defmodule Hexpm.Repository.Policy.Override do
  @moduledoc """
  A package-scoped policy decision. `allow` and `deny` decide the release,
  while `advisory`, `retirement`, and `cooldown` bypass one matching
  restriction. The optional requirement narrows the override to matching
  releases.
  """
  use Hexpm.Schema

  alias Hexpm.Repository.Policy
  alias Hexpm.Security.Advisories

  @package_format ~r/^[a-z0-9][a-z0-9_\-\.]*[a-z0-9]$/
  @comment_format ~r/^[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}]*$/u

  embedded_schema do
    field :action, Ecto.Enum, values: [:allow, :deny, :advisory, :retirement, :cooldown]
    field :package, :string
    field :requirement, :string
    field :advisory_id, :string
    field :retirement_reason, :integer
    field :comment, :string
  end

  def changeset(override, attrs, repository \\ nil) do
    override
    |> cast(attrs, [
      :action,
      :package,
      :requirement,
      :advisory_id,
      :retirement_reason,
      :comment
    ])
    |> update_change(:requirement, &nilify_blank/1)
    |> update_change(:advisory_id, &nilify_blank/1)
    |> update_change(:comment, &nilify_blank/1)
    |> validate_required([:action, :package])
    |> validate_package()
    |> validate_requirement()
    |> validate_retirement_reason()
    |> validate_selector()
    |> validate_comment()
    |> validate_advisory(repository)
  end

  defp validate_package(changeset) do
    case get_field(changeset, :package) do
      package when is_binary(package) ->
        if String.valid?(package) do
          validate_format(changeset, :package, @package_format)
        else
          add_error(changeset, :package, "has invalid format")
        end

      _package ->
        changeset
    end
  end

  defp validate_requirement(changeset) do
    case get_field(changeset, :requirement) do
      nil ->
        changeset

      requirement ->
        validate_parsed_requirement(changeset, requirement)
    end
  end

  defp validate_parsed_requirement(changeset, requirement) do
    if String.valid?(requirement) do
      case Version.parse_requirement(requirement) do
        {:ok, _} -> changeset
        :error -> add_error(changeset, :requirement, "is invalid")
      end
    else
      add_error(changeset, :requirement, "is invalid")
    end
  rescue
    _error -> add_error(changeset, :requirement, "is invalid")
  end

  defp validate_retirement_reason(changeset) do
    case get_field(changeset, :retirement_reason) do
      nil ->
        changeset

      reason ->
        if Map.has_key?(Policy.retirement_reasons(), reason) do
          changeset
        else
          add_error(changeset, :retirement_reason, "is invalid")
        end
    end
  end

  defp validate_selector(changeset) do
    case {
      get_field(changeset, :action),
      get_field(changeset, :advisory_id),
      get_field(changeset, :retirement_reason)
    } do
      {nil, _advisory_id, _retirement_reason} ->
        changeset

      {action, nil, nil} when action in [:allow, :deny, :cooldown] ->
        changeset

      {:advisory, advisory_id, nil} when is_binary(advisory_id) ->
        changeset

      {:retirement, nil, retirement_reason} when is_integer(retirement_reason) ->
        changeset

      _other ->
        add_error(changeset, :action, "does not match its selector fields")
    end
  end

  defp validate_comment(changeset) do
    case get_field(changeset, :comment) do
      nil ->
        changeset

      comment when is_binary(comment) ->
        if String.valid?(comment) do
          changeset
          |> validate_comment_length()
          |> validate_format(:comment, @comment_format,
            message: "contains invalid control, format, or separator characters"
          )
        else
          add_error(
            changeset,
            :comment,
            "contains invalid control, format, or separator characters"
          )
        end
    end
  end

  defp validate_comment_length(changeset) do
    validate_change(changeset, :comment, fn :comment, comment ->
      if length(String.to_charlist(comment)) <= 500 do
        []
      else
        [comment: "should be at most 500 character(s)"]
      end
    end)
  end

  defp validate_advisory(changeset, repository) do
    advisory_id = get_field(changeset, :advisory_id)
    package = get_field(changeset, :package)

    cond do
      get_field(changeset, :action) != :advisory ->
        changeset

      not is_binary(advisory_id) or not String.valid?(advisory_id) ->
        add_error(changeset, :advisory_id, "is not an active advisory for this package")

      not is_binary(package) or not String.valid?(package) ->
        changeset

      Advisories.valid_policy_exception?(repository, package, advisory_id) ->
        changeset

      true ->
        add_error(changeset, :advisory_id, "is not an active advisory for this package")
    end
  end

  defp nilify_blank(nil), do: nil

  defp nilify_blank(value) when is_binary(value) do
    if String.valid?(value), do: trim_or_nil(value), else: value
  end

  defp trim_or_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

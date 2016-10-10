defmodule HexWeb.Validation do
  @moduledoc """
  Ecto validation helpers.
  """

  import Ecto.Changeset

  @doc """
  Checks if a version is valid semver.
  """
  def validate_version(changeset, field) do
    validate_change(changeset, field, fn
      _, %Version{build: nil} ->
        []
      _, %Version{} ->
        [{field, "build number not allowed"}]
    end)
  end

  def validate_list_required(changeset, field) do
    validate_change(changeset, field, fn
      _, [] ->
        [{field, "can't be blank"}]
      _, list when is_list(list) ->
        []
    end)
  end

  def validate_password(changeset, field, hash, opts \\ []) do
    error_param = "#{field}_current"
    error_field = String.to_atom(error_param)

    errors =
      case Map.fetch(changeset.params, error_param) do
        {:ok, value} ->
          hash = default_hash(hash)
          if Comeonin.Bcrypt.checkpw(value, hash),
            do: [],
          else: [{error_field, {"is invalid", []}}]

        :error ->
          [{error_field, {"can't be blank", []}}]
      end

    %{changeset | validations: [{:password, opts}|changeset.validations],
                  errors: errors ++ changeset.errors,
                  valid?: changeset.valid? and errors == []}
  end

  defp default_hash(nil), do: Comeonin.Bcrypt.hashpwsalt("password")
  defp default_hash(""), do: Comeonin.Bcrypt.hashpwsalt("password")
  defp default_hash(password), do: password
end

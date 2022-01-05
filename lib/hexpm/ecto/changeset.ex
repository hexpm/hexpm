defmodule Hexpm.Changeset do
  @moduledoc """
  Ecto changeset helpers.
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

  def validate_list_required(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn
      _, [] ->
        [{field, Keyword.get(opts, :message, "can't be blank")}]

      _, list when is_list(list) ->
        []
    end)
  end

  def validate_requirement(changeset, field) do
    validate_change(changeset, field, fn key, req ->
      cond do
        is_nil(req) ->
          [{key, "invalid requirement: #{inspect(req)}, use \">= 0.0.0\" instead"}]

        not valid_requirement?(req) ->
          [{key, "invalid requirement: #{inspect(req)}"}]

        String.contains?(req, "!=") ->
          [{key, "invalid requirement: #{inspect(req)}, != is not allowed in requirements"}]

        true ->
          []
      end
    end)
  end

  defp valid_requirement?(req) do
    is_binary(req) and match?({:ok, _}, Version.parse_requirement(req))
  end

  def validate_verified_email_exists(changeset, field, opts) do
    validate_change(changeset, field, fn _, email ->
      case Hexpm.Repo.get_by(Hexpm.Accounts.Email, email: email, verified: true) do
        nil ->
          []

        _ ->
          [{field, opts[:message]}]
      end
    end)
  end

  def validate_repository(changeset, field, opts) do
    validate_change(changeset, field, fn key, dependency_repository ->
      organization = Keyword.fetch!(opts, :repository)

      if dependency_repository in ["hexpm", organization.name] do
        []
      else
        [{key, {repository_error(organization, dependency_repository), []}}]
      end
    end)
  end

  defp repository_error(%{id: 1}, dependency_repository) do
    "dependencies can only belong to public repository \"hexpm\", " <>
      "got: #{inspect(dependency_repository)}"
  end

  defp repository_error(%{name: name}, dependency_repository) do
    "dependencies can only belong to public repository \"hexpm\" " <>
      "or current repository #{inspect(name)}, got: #{inspect(dependency_repository)}"
  end

  def validate_password(changeset, field, hash, opts \\ []) do
    error_param = "#{field}_current"
    error_field = String.to_atom(error_param)

    errors =
      case Map.fetch(changeset.params, error_param) do
        {:ok, value} ->
          hash = default_hash(hash)

          if Bcrypt.verify_pass(value, hash),
            do: [],
            else: [{error_field, {"is invalid", []}}]

        :error ->
          [{error_field, {"can't be blank", []}}]
      end

    %{
      changeset
      | validations: [{:password, opts} | changeset.validations],
        errors: errors ++ changeset.errors,
        valid?: changeset.valid? and errors == []
    }
  end

  @default_password Bcrypt.hash_pwd_salt("password")

  defp default_hash(nil), do: @default_password
  defp default_hash(""), do: @default_password
  defp default_hash(password), do: password

  def put_default_embed(changeset, key, value) do
    if get_change(changeset, key) do
      changeset
    else
      put_embed(changeset, key, value)
    end
  end
end

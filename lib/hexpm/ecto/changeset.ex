defmodule Hexpm.Changeset do
  @moduledoc """
  Ecto changeset helpers.
  """

  import Ecto.Changeset

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

  @doc """
  Every entry of a list field has to be a string of at most `max` units, where
  `count` is `:bytes` or `:codepoints`.
  """
  def validate_each_length(changeset, field, opts) do
    max = Keyword.fetch!(opts, :max)
    count = Keyword.fetch!(opts, :count)

    validate_change(changeset, field, fn _, list ->
      if Enum.all?(list, &(is_binary(&1) and string_length(&1, count) <= max)) do
        []
      else
        [{field, {"entries should be at most %{count} #{unit(count)}", count: max}}]
      end
    end)
  end

  @doc """
  A map field has at most `max_entries` entries, every key is a string of at
  most `key_max` units and every string value is at most `value_max` units,
  counted in `key_count` and `value_count` (`:bytes` or `:codepoints`).
  """
  def validate_map_entries(changeset, field, opts) do
    max_entries = Keyword.fetch!(opts, :max_entries)
    key_max = Keyword.fetch!(opts, :key_max)
    key_count = Keyword.fetch!(opts, :key_count)
    value_max = Keyword.fetch!(opts, :value_max)
    value_count = Keyword.fetch!(opts, :value_count)

    validate_change(changeset, field, fn _, map ->
      cond do
        map_size(map) > max_entries ->
          [{field, {"should have at most %{count} entry(ies)", count: max_entries}}]

        not Enum.all?(map, fn {key, _} ->
          is_binary(key) and string_length(key, key_count) <= key_max
        end) ->
          [{field, {"keys should be at most %{count} #{unit(key_count)}", count: key_max}}]

        not Enum.all?(map, fn {_, value} ->
          is_binary(value) and string_length(value, value_count) <= value_max
        end) ->
          [{field, {"values should be at most %{count} #{unit(value_count)}", count: value_max}}]

        true ->
          []
      end
    end)
  end

  defp string_length(string, :bytes), do: byte_size(string)
  defp string_length(string, :codepoints), do: length(String.codepoints(string))

  defp unit(:bytes), do: "byte(s)"
  defp unit(:codepoints), do: "character(s)"

  @doc """
  The JSON encoding of a field is at most `max` bytes.
  """
  def validate_encoded_size(changeset, field, max: max) do
    validate_change(changeset, field, fn _, value ->
      case encoded_size(value) do
        {:ok, size} when size <= max -> []
        {:ok, _size} -> [{field, {"should be at most %{count} byte(s) when encoded", count: max}}]
        :error -> [{field, "is invalid"}]
      end
    end)
  end

  defp encoded_size(value) do
    {:ok, IO.iodata_length(JSON.encode_to_iodata!(value))}
  rescue
    _ -> :error
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
            else: [{error_field, {"incorrect password", []}}]

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

  def nilify_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def nilify_blank(value), do: value

  def put_default_embed(changeset, key, value) do
    if get_change(changeset, key) do
      changeset
    else
      put_embed(changeset, key, value)
    end
  end
end

defmodule Hexpm.Accounts.OptionalEmails do
  @moduledoc """
  Defines optional emails that users can opt out of.
  Example:
   if OptionalEmails.allowed?(user, :org_invite) do
      Emails.organization_invite(organization, user)
      |> Mailer.deliver_later!()
    end
  """

  @types [
    %{
      id: :org_invite,
      title: "Organization invites",
      description_enabled: "You’ll be notified whenever an organization you belong to adds you.",
      description_disabled:
        "You will not be notified when an organization you belong to adds you.",
      optional: true
    }
  ]

  @doc "Returns the metadata for every supported optional email."
  def list do
    @types
  end

  @doc "Returns the allowed ids."
  def ids do
    Enum.map(@types, & &1.id)
  end

  @doc "Returns the normalized preferences for the given user."
  def preferences(user) do
    stored = user.optional_emails || %{}

    Enum.into(@types, %{}, fn %{id: id} ->
      key = to_string(id)
      {key, Map.get(stored, key, true)}
    end)
  end

  @doc "Returns defaults for every optional email."
  def default_preferences do
    Enum.into(@types, %{}, fn %{id: id} ->
      {to_string(id), true}
    end)
  end

  @doc "Normalizes the raw params from the settings form."
  def normalize_preferences(params) when is_map(params) do
    Enum.into(@types, %{}, fn %{id: id} ->
      key = to_string(id)
      value = params[key] || params[String.to_atom(key)]
      {key, to_bool(value)}
    end)
  end

  def normalize_preferences(_), do: default_preferences()

  @doc "Validates a preferences map contains only allowed keys with boolean values."
  def validate_preferences_map(map) when is_map(map) do
    allowed_keys = Enum.map(@types, &to_string(&1.id))

    map
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      cond do
        key not in allowed_keys -> {:halt, :error}
        is_boolean(value) -> {:cont, {:ok, Map.put(acc, key, value)}}
        true -> {:halt, :error}
      end
    end)
  end

  def validate_preferences_map(_), do: :error

  @doc "Returns whether a given optional email is allowed for the user."
  def allowed?(user, id) do
    preferences(user)
    |> Map.get(to_string(id), true)
  end

  defp to_bool(value) do
    value
    |> String.downcase()
    |> case do
      "true" -> true
      "false" -> false
      _ -> false
    end
  end
end

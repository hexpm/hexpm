defmodule Hexpm.Accounts.OptionalEmails do
  @moduledoc """
  Defines optional emails that users can opt out of.
  Example:
   if OptionalEmails.allowed?(user, :organization_invite) do
      Emails.organization_invite(organization, user)
      |> Mailer.deliver!()
    end
  """

  @types [
    %{
      id: :organization_invite,
      title: "Organization invites",
      description: "You’ll be notified when you are invited to an organization."
    },
    %{
      id: :owner_added_to_package,
      title: "Owner added to package",
      description:
        "You’ll be notified whenever an owner is added to a package you own or when you are added as an owner."
    },
    %{
      id: :owner_removed_from_package,
      title: "Owner removed from package",
      description:
        "You’ll be notified whenever an owner is removed from a package you own or when you are removed as an owner."
    },
    %{
      id: :package_published,
      title: "Package published",
      description: "You’ll be notified whenever a package you own is published."
    },
    %{
      id: :api_key_created,
      title: "API key created",
      description:
        "You’ll be notified whenever a key is created on your account or on an organization you administer."
    },
    %{
      id: :api_key_revoked,
      title: "API key revoked",
      description:
        "You’ll be notified whenever a key is revoked on your account or on an organization you administer."
    },
    %{
      id: :workload_identity_changed,
      title: "Workload identity changes",
      description:
        "You’ll be notified whenever a workload identity is added, changed or removed on a package you own or an organization you administer."
    },
    %{
      id: :staged_release_ready,
      title: "Staged release ready to approve",
      description: "You’ll be notified when a release you can approve is staged."
    },
    %{
      id: :staged_release_expired,
      title: "Staged release expired",
      description:
        "You’ll be notified when a staged release you could approve expires without being approved."
    },
    %{
      id: :sso_seats,
      title: "Organization SSO seats",
      description:
        "You’ll be notified when an organization you administer runs out of SSO seats, can’t add a seat, or can’t read its seat count."
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
      value = params[key]
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

  defp to_bool(nil), do: false

  defp to_bool(value) when is_binary(value) do
    value
    |> String.downcase()
    |> case do
      "true" -> true
      "false" -> false
      _ -> false
    end
  end

  defp to_bool(value) when is_boolean(value), do: value
  defp to_bool(_), do: false
end

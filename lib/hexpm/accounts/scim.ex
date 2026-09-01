defmodule Hexpm.Accounts.SCIM do
  @moduledoc """
  The SCIM Users resource: what the provider's provisioning agent reads and
  writes through `/scim/v2/Users`.

  Assignment creates membership when a verified email names an existing
  account, and a pending invitation otherwise; deactivation removes the
  membership or revokes the invitation. The resource rows are handles, not
  state: whether a person is a member is derived from `organization_users` on
  every read, so membership changed by hand shows up on the provider's next
  request. SCIM writes membership but never owns it.

  Every write acts as the organization itself in the audit log, through the
  same `organization.member.*` and `organization.invitation.*` actions the
  dashboard writes.
  """

  use Hexpm.Context

  alias Hexpm.Accounts.SCIM.Resource
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Connection, Identity}

  @type resolved :: %{
          resource: Resource.t(),
          state: :member | :invited | :inactive,
          user: User.t() | nil
        }

  @doc """
  The listing the provider's import reads: every current member, materialized
  into a resource row on first sight, plus the rows in invited or inactive
  states. `start_index` is SCIM's 1-based offset.
  """
  def list_users(%Connection{} = connection, start_index, count) do
    materialize_members(connection)

    total = Repo.aggregate(resources_query(connection), :count)

    resources =
      from(resource in resources_query(connection),
        order_by: resource.id,
        offset: ^(start_index - 1),
        limit: ^count
      )
      |> Repo.all()
      |> Enum.map(&resolve/1)

    %{total: total, start_index: start_index, resources: resources}
  end

  @doc """
  The provider's match key. A row wins; otherwise a current member whose
  verified email this is gets a row materialized, which is how people who
  joined before provisioning was turned on are matched by an import.
  """
  def find_by_user_name(%Connection{} = connection, user_name) when is_binary(user_name) do
    user_name = Resource.normalize_user_name(user_name)

    case get_resource_by_user_name(connection, user_name) do
      %Resource{} = resource ->
        resolve(resource)

      nil ->
        case verified_email_owner(user_name) do
          %User{} = user ->
            if member?(connection.organization_id, user.id) do
              materialize_member(connection, user, user_name)
            end

          nil ->
            nil
        end
    end
  end

  def find_by_external_id(%Connection{} = connection, external_id)
      when is_binary(external_id) do
    case Repo.one(
           from(resource in resources_query(connection),
             where: resource.external_id == ^external_id
           )
         ) do
      %Resource{} = resource -> resolve(resource)
      nil -> nil
    end
  end

  def get_user(%Connection{} = connection, scim_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(scim_id),
         %Resource{} = resource <-
           Repo.one(
             from(resource in resources_query(connection), where: resource.scim_id == ^uuid)
           ) do
      {:ok, resolve(resource)}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc """
  Creates the resource, and the membership or invitation behind it unless the
  payload arrives deactivated. A duplicate `userName` is the provider's signal
  to fall back to filtering and patching, so it fails rather than adopting.
  """
  def create_user(%Connection{} = connection, params) do
    with {:ok, user_name} <- validate_user_name(params["userName"]) do
      external_id = optional_string(params["externalId"])

      cond do
        get_resource_by_user_name(connection, user_name) ->
          {:error, :uniqueness}

        active_value(params["active"], true) == false ->
          insert_resource(connection, %{user_name: user_name, external_id: external_id})

        true ->
          create_active(connection, user_name, external_id)
      end
    end
  end

  @doc """
  Full replace of the attributes we own: `userName`, `externalId`, and the
  `active` transition. Everything else in the payload is ignored.
  """
  def replace_user(%Connection{} = connection, scim_id, params) do
    with {:ok, resolved} <- get_user(connection, scim_id),
         {:ok, user_name} <- validate_user_name(params["userName"]) do
      apply_changes(connection, resolved, %{
        user_name: user_name,
        external_id: optional_string(params["externalId"]),
        active: active_value(params["active"], true)
      })
    end
  end

  @doc """
  The minimal patch set the providers use: replace or add on `active`,
  `userName`, and `externalId`, with Entra's string booleans normalized.
  Operations on attributes we do not store are ignored.
  """
  def patch_user(%Connection{} = connection, scim_id, operations) when is_list(operations) do
    with {:ok, resolved} <- get_user(connection, scim_id) do
      # Operations run one at a time, in array order, as RFC 7644 requires:
      # `active` then `userName` means activate the account this name matches
      # now and relabel afterwards, which is not the same as activating under
      # the final name.
      Enum.reduce_while(operations, {:ok, resolved}, fn operation, {:ok, resolved} ->
        case patch_change(operation) do
          {:ok, change} ->
            case apply_changes(connection, resolved, change) do
              {:ok, resolved} -> {:cont, {:ok, resolved}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          :ignore ->
            {:cont, {:ok, resolved}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end
  end

  def patch_user(%Connection{}, _scim_id, _operations), do: {:error, :invalid_path}

  @doc """
  Deactivates, then deletes the handle, freeing the `userName` slot. Sent by
  Entra on permanent deletion; Okta deactivates instead.
  """
  def delete_user(%Connection{} = connection, scim_id) do
    with {:ok, resolved} <- get_user(connection, scim_id),
         {:ok, resolved} <- deactivate(connection, resolved) do
      Repo.delete!(resolved.resource)
      :ok
    end
  end

  # -- state resolution ------------------------------------------------------

  # Derives the state and performs the two lazy repairs: an accepted
  # invitation hands its account over, and a userName newly verified by a
  # current member adopts the membership.
  defp resolve(%Resource{} = resource) do
    resource = resource |> Repo.preload([:user, :invitation]) |> repair()

    cond do
      resource.user_id && member?(resource.organization_id, resource.user_id) ->
        %{resource: resource, state: :member, user: resource.user}

      pending?(resource.invitation) ->
        %{resource: resource, state: :invited, user: nil}

      true ->
        %{resource: resource, state: :inactive, user: resource.user}
    end
  end

  defp repair(
         %Resource{user_id: nil, invitation: %OrganizationInvitation{} = invitation} = resource
       )
       when not is_nil(invitation.accepted_by_user_id) do
    adopt_user(resource, invitation.accepted_by_user_id)
  end

  defp repair(%Resource{user_id: nil} = resource) do
    with %User{} = user <- verified_email_owner(resource.user_name),
         true <- member?(resource.organization_id, user.id) do
      adopt_user(resource, user.id)
    else
      _no_match -> resource
    end
  end

  defp repair(resource), do: resource

  defp adopt_user(resource, user_id) do
    resource
    |> change(user_id: user_id)
    |> unique_constraint([:connection_id, :user_id])
    |> Repo.update()
    |> case do
      {:ok, resource} -> Repo.preload(resource, :user, force: true)
      # Another resource already holds this account; leave this one alone.
      {:error, _changeset} -> resource
    end
  end

  defp pending?(%OrganizationInvitation{} = invitation),
    do: OrganizationInvitation.pending?(invitation, DateTime.utc_now())

  defp pending?(_invitation), do: false

  # -- create and activation -------------------------------------------------

  defp create_active(connection, user_name, external_id) do
    case verified_email_owner(user_name) do
      %User{} = user ->
        create_member(connection, user_name, external_id, user, _retried? = false)

      nil ->
        with {:ok, invitation, _provenance} <- obtain_invitation(connection, user_name) do
          insert_resource(connection, %{
            user_name: user_name,
            external_id: external_id,
            invitation_id: invitation.id
          })
        end
    end
  end

  defp create_member(connection, user_name, external_id, user, retried?) do
    attrs = %{user_name: user_name, external_id: external_id, user_id: user.id}

    result =
      Repo.transaction(fn ->
        with :ok <- ensure_membership(connection, user) do
          case do_insert_resource(connection, attrs) do
            {:ok, resource} -> resource
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, resource} ->
        {:ok, resolve(resource)}

      {:error, :seats_exhausted} when not retried? ->
        retry_after_expansion(connection, fn ->
          create_member(connection, user_name, external_id, user, true)
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Reactivation of an existing handle: the same matching as a create, applied
  # to the row the provider already holds.
  defp activate(_connection, %{state: state} = resolved) when state in [:member, :invited] do
    {:ok, resolved}
  end

  defp activate(connection, %{resource: resource}) do
    activate_resource(connection, resource, _retried? = false)
  end

  defp activate_resource(connection, resource, retried?) do
    case verified_email_owner(resource.user_name) do
      %User{} = user ->
        result =
          Repo.transaction(fn ->
            with :ok <- ensure_membership(connection, user) do
              case update_resource(resource, %{user_id: user.id}) do
                {:ok, resource} -> resource
                {:error, reason} -> Repo.rollback(reason)
              end
            else
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        case result do
          {:ok, resource} ->
            {:ok, resolve(resource)}

          {:error, :seats_exhausted} when not retried? ->
            retry_after_expansion(connection, fn ->
              activate_resource(connection, resource, true)
            end)

          {:error, reason} ->
            {:error, reason}
        end

      nil ->
        with {:ok, invitation, _provenance} <- obtain_invitation(connection, resource.user_name),
             {:ok, resource} <- update_resource(resource, %{invitation_id: invitation.id}) do
          {:ok, resolve(resource)}
        end
    end
  end

  # The seat is claimed and the membership inserted in the caller's
  # transaction. A concurrent membership (JIT, an administrator) is adopted
  # rather than refused: the person the provider asked for is a member.
  defp ensure_membership(connection, user) do
    organization = connection.organization

    cond do
      User.organization?(user) ->
        {:error, :invalid_value}

      Organizations.get_role(organization, user) ->
        :ok

      true ->
        case Seats.claim(organization, unknown: :deny) do
          {:ok, _usage} ->
            organization_user = %OrganizationUser{
              organization_id: organization.id,
              user_id: user.id
            }

            case Repo.insert(
                   Organization.add_member(organization_user, %{"role" => connection.scim_role})
                 ) do
              {:ok, _member} ->
                audit!(organization, "organization.member.add", {organization, user})
                :ok

              {:error, %Ecto.Changeset{} = changeset} ->
                if unique_violation?(changeset), do: :ok, else: {:error, changeset}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp retry_after_expansion(connection, retry) do
    if connection.scim_seat_policy == "expand" do
      SSO.expand_seat(connection, :scim)
      retry.()
    else
      {:error, :seats_exhausted}
    end
  end

  defp obtain_invitation(connection, user_name) do
    organization = connection.organization

    case OrganizationInvitations.get_pending_by_email(organization, user_name) do
      %OrganizationInvitation{} = invitation ->
        {:ok, invitation, :adopted}

      nil ->
        case OrganizationInvitations.invite(
               organization,
               %{"email" => user_name, "role" => connection.scim_role},
               nil,
               audit: AuditLogs.system(organization)
             ) do
          {:ok, invitation} ->
            {:ok, invitation, :created}

          # `invite/4` matched a member through a username or an unverified
          # address. A verified email never reached this branch, so binding
          # the account here would trust exactly what the design refuses to.
          {:error, :already_member} ->
            {:error, :unverified_member}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  # -- attribute changes and deactivation ------------------------------------

  defp apply_changes(connection, resolved, changes) do
    with {:ok, resolved} <- apply_attributes(connection, resolved, changes) do
      case Map.fetch(changes, :active) do
        {:ok, true} -> activate(connection, resolved)
        {:ok, false} -> deactivate(connection, resolved)
        :error -> {:ok, resolved}
      end
    end
  end

  defp apply_attributes(connection, resolved, changes) do
    with {:ok, resolved} <- apply_user_name(connection, resolved, changes) do
      case Map.fetch(changes, :external_id) do
        {:ok, external_id} ->
          with {:ok, resource} <- update_resource(resolved.resource, %{external_id: external_id}) do
            {:ok, %{resolved | resource: resource}}
          end

        :error ->
          {:ok, resolved}
      end
    end
  end

  defp apply_user_name(connection, resolved, %{user_name: user_name}) do
    user_name = Resource.normalize_user_name(user_name)

    cond do
      user_name == resolved.resource.user_name ->
        {:ok, resolved}

      not Resource.email_shaped?(user_name) ->
        {:error, :invalid_value}

      # While a membership stands the name is a label; deactivate and
      # reactivate is the account-transfer path.
      resolved.state in [:member, :inactive] ->
        with {:ok, resource} <- update_resource(resolved.resource, %{user_name: user_name}) do
          {:ok, %{resolved | resource: resource}}
        end

      # An invited person renamed is an invitation to the new address. The
      # row is updated before the old invitation is retired, so a rename that
      # fails on a taken name leaves the original untouched; only an
      # invitation this rename itself created is taken back on failure.
      resolved.state == :invited ->
        old_invitation_id = resolved.resource.invitation_id

        with {:ok, invitation, provenance} <- obtain_invitation(connection, user_name) do
          case update_resource(resolved.resource, %{
                 user_name: user_name,
                 invitation_id: invitation.id
               }) do
            {:ok, resource} ->
              retire_invitation(connection, old_invitation_id)
              {:ok, resolve(resource)}

            {:error, reason} ->
              if provenance == :created do
                retire_invitation(connection, invitation.id)
              end

              {:error, reason}
          end
        end
    end
  end

  defp apply_user_name(_connection, resolved, _changes), do: {:ok, resolved}

  defp deactivate(connection, %{state: :member} = resolved) do
    organization = connection.organization

    case Organizations.remove_member(organization, resolved.user,
           audit: AuditLogs.system(organization)
         ) do
      :ok -> retire_and_clear(connection, resolved.resource)
      {:error, :last_member} -> {:error, :last_member}
    end
  end

  defp deactivate(connection, %{state: :invited} = resolved) do
    retire_and_clear(connection, resolved.resource)
  end

  defp deactivate(_connection, %{state: :inactive} = resolved), do: {:ok, resolved}

  # What a deactivation leaves behind: no live invitation that could re-admit
  # the address, no membership created by an acceptance that raced it, and no
  # dangling pointer on the handle.
  defp retire_and_clear(connection, resource) do
    case retire_invitation(connection, resource.invitation_id) do
      {:accepted, user_id} ->
        organization = connection.organization
        acceptor = user_id && Repo.get(User, user_id)

        remove =
          if acceptor && Organizations.get_role(organization, acceptor) do
            Organizations.remove_member(organization, acceptor,
              audit: AuditLogs.system(organization)
            )
          else
            :ok
          end

        case remove do
          {:error, :last_member} -> {:error, :last_member}
          :ok -> clear_invitation(resource)
        end

      _retired ->
        clear_invitation(resource)
    end
  end

  defp clear_invitation(resource) do
    with {:ok, resource} <- update_resource(resource, %{invitation_id: nil}) do
      {:ok, resolve(resource)}
    end
  end

  # Revokes under a row lock, or reports that an acceptance won the race, so
  # revocation never stamps an accepted row while its membership walks away.
  defp retire_invitation(_connection, nil), do: :none

  defp retire_invitation(connection, invitation_id) do
    {:ok, outcome} =
      Repo.transaction(fn ->
        locked =
          Repo.one(
            from(invitation in OrganizationInvitation,
              where: invitation.id == ^invitation_id,
              lock: "FOR UPDATE"
            )
          )

        cond do
          is_nil(locked) ->
            :none

          locked.accepted_at ->
            {:accepted, locked.accepted_by_user_id}

          is_nil(locked.revoked_at) ->
            {:ok, _invitation} =
              OrganizationInvitations.revoke(connection.organization, locked,
                audit: AuditLogs.system(connection.organization)
              )

            :revoked

          true ->
            :none
        end
      end)

    outcome
  end

  # -- materialization -------------------------------------------------------

  defp materialize_members(connection) do
    represented =
      from(resource in resources_query(connection),
        where: not is_nil(resource.user_id),
        select: resource.user_id
      )
      |> Repo.all()
      |> MapSet.new()

    provider_emails =
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        select: {identity.user_id, identity.provider_email}
      )
      |> Repo.all()
      |> Map.new()

    for organization_user <- Organizations.all_members(connection.organization, user: :emails),
        organization_user.user_id not in represented do
      user = organization_user.user
      user_name = provider_emails[user.id] || primary_email(user)

      if user_name do
        materialize_member(connection, user, user_name)
      end
    end

    :ok
  end

  # Best-effort under races and collisions: `on_conflict: :nothing` covers a
  # concurrent import or two members presenting the same address, and the read
  # path re-resolves whatever row won.
  defp materialize_member(connection, user, user_name) do
    connection
    |> Resource.build()
    |> Resource.changeset(%{user_name: user_name, user_id: user.id})
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, %Resource{id: nil}} -> refetch(connection, user_name)
      {:ok, resource} -> resolve(resource)
      {:error, _changeset} -> refetch(connection, user_name)
    end
  end

  defp refetch(connection, user_name) do
    case get_resource_by_user_name(connection, user_name) do
      %Resource{} = resource -> resolve(resource)
      nil -> nil
    end
  end

  # Verified as well as primary: presenting an unverified address as the
  # match key would let the handle bind to whoever typed the address first
  # rather than whoever owns it.
  defp primary_email(user) do
    Enum.find_value(user.emails, fn email -> email.verified && email.primary && email.email end)
  end

  # -- persistence helpers ---------------------------------------------------

  defp insert_resource(connection, attrs) do
    with {:ok, resource} <- do_insert_resource(connection, attrs) do
      {:ok, resolve(resource)}
    end
  end

  defp do_insert_resource(connection, attrs) do
    connection
    |> Resource.build()
    |> Resource.changeset(attrs)
    |> Repo.insert()
    |> normalize_write_error()
  end

  defp update_resource(resource, attrs) do
    resource
    |> Resource.changeset(attrs)
    |> Repo.update()
    |> normalize_write_error()
  end

  defp normalize_write_error({:ok, resource}), do: {:ok, resource}

  defp normalize_write_error({:error, %Ecto.Changeset{} = changeset}) do
    if unique_violation?(changeset), do: {:error, :uniqueness}, else: {:error, changeset}
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)
  end

  defp resources_query(connection) do
    from(resource in Resource, where: resource.connection_id == ^connection.id)
  end

  defp get_resource_by_user_name(connection, user_name) do
    Repo.get_by(Resource, connection_id: connection.id, user_name: user_name)
  end

  defp verified_email_owner(user_name) do
    case Users.get_email(user_name, [:user]) do
      %{user: %User{} = user} -> unless User.organization?(user), do: user
      _missing -> nil
    end
  end

  defp member?(organization_id, user_id) do
    Repo.exists?(
      from(organization_user in OrganizationUser,
        where: organization_user.organization_id == ^organization_id,
        where: organization_user.user_id == ^user_id
      )
    )
  end

  defp audit!(organization, action, params) do
    organization
    |> AuditLogs.system()
    |> AuditLog.build(action, params)
    |> Repo.insert!()
  end

  # -- SCIM value parsing ----------------------------------------------------

  defp validate_user_name(user_name) when is_binary(user_name) do
    user_name = Resource.normalize_user_name(user_name)

    if Resource.email_shaped?(user_name) do
      {:ok, user_name}
    else
      {:error, :invalid_value}
    end
  end

  defp validate_user_name(_user_name), do: {:error, :invalid_value}

  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: nil

  defp active_value(value, default) do
    case value do
      nil -> default
      true -> true
      false -> false
      "true" -> true
      "True" -> true
      "false" -> false
      "False" -> false
      _other -> default
    end
  end

  defp patch_change(%{"op" => op} = operation) do
    path = operation |> Map.get("path") |> normalize_path()
    value = Map.get(operation, "value")

    case {String.downcase(to_string(op)), path} do
      {op, nil} when op in ["replace", "add"] and is_map(value) ->
        {:ok, value_object_changes(value)}

      {op, "active"} when op in ["replace", "add"] ->
        {:ok, %{active: active_value(value, true)}}

      {op, "username"} when op in ["replace", "add"] and is_binary(value) ->
        {:ok, %{user_name: value}}

      {op, "externalid"} when op in ["replace", "add"] ->
        {:ok, %{external_id: optional_string(value)}}

      {"remove", "externalid"} ->
        {:ok, %{external_id: nil}}

      {"remove", path} when path in ["active", "username"] ->
        {:error, :invalid_path}

      # Attributes we do not store; the echo never includes them, so there is
      # nothing for the operation to change.
      {op, _ignored} when op in ["replace", "add", "remove"] ->
        :ignore

      _unknown ->
        {:error, :invalid_path}
    end
  end

  defp patch_change(_operation), do: {:error, :invalid_path}

  defp normalize_path(nil), do: nil

  defp normalize_path(path) when is_binary(path) do
    path
    |> String.replace_prefix("urn:ietf:params:scim:schemas:core:2.0:User:", "")
    |> String.downcase()
  end

  defp value_object_changes(value) do
    Enum.reduce(value, %{}, fn
      {"active", active}, changes ->
        Map.put(changes, :active, active_value(active, true))

      {"userName", user_name}, changes when is_binary(user_name) ->
        Map.put(changes, :user_name, user_name)

      {"externalId", external_id}, changes ->
        Map.put(changes, :external_id, optional_string(external_id))

      {_other, _value}, changes ->
        changes
    end)
  end
end

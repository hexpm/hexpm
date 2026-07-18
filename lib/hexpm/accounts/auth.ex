defmodule Hexpm.Accounts.Auth do
  import Ecto.Query, only: [from: 2]
  import HexpmWeb.RequestHelpers, only: [parse_ip: 1, parse_user_agent: 1]

  alias Hexpm.Accounts.{Key, Keys, Organization, Organizations, User, Users, UserProviders}
  alias Hexpm.OAuth.{JWT, MachineToken, Tokens}
  alias Hexpm.Permissions

  def key_auth(user_secret, usage_info, opts \\ []) do
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    preload = Keyword.get(opts, :preload, :full)

    result =
      key_auth_query(first, preload)
      |> Hexpm.Repo.one()

    case result do
      nil ->
        :error

      key ->
        valid_auth = !key.user || not User.organization?(key.user)

        if valid_auth && Hexpm.Utils.secure_check(key.secret_second, second) do
          if Key.revoked?(key) do
            :revoked
          else
            Keys.update_last_use(key, usage_info(usage_info))

            {:ok,
             %{
               auth_credential: key,
               user: key.user,
               organization: key.organization,
               email: if(preload == :full, do: find_email(key.user, nil))
             }}
          end
        else
          :error
        end
    end
  end

  defp key_auth_query(first, :full) do
    from(
      k in Key,
      where: k.secret_first == ^first,
      left_join: u in assoc(k, :user),
      left_join: o in assoc(k, :organization),
      preload: [user: {u, [:emails, owned_packages: :repository, organizations: :repository]}],
      preload: [organization: {o, [:repository, user: [:emails, owned_packages: :repository]]}]
    )
  end

  # Lightweight preload for OAuth token endpoint: only loads user with organizations
  # (for scope expansion) and organization. Skips emails and owned_packages
  # which are not needed for token issuance.
  defp key_auth_query(first, :oauth) do
    from(
      k in Key,
      where: k.secret_first == ^first,
      left_join: u in assoc(k, :user),
      left_join: o in assoc(k, :organization),
      preload: [user: {u, [:organizations]}],
      preload: [organization: o]
    )
  end

  def password_auth(username_or_email, password) do
    user =
      Users.get(username_or_email, [
        :emails,
        owned_packages: :repository,
        organizations: :repository
      ])

    valid_user = user && not User.organization?(user) && user.password

    if valid_user && Bcrypt.verify_pass(password, user.password) do
      {:ok,
       %{
         auth_credential: nil,
         user: user,
         organization: nil,
         email: find_email(user, username_or_email)
       }}
    else
      :error
    end
  end

  def gen_password(nil), do: nil
  def gen_password(password), do: Bcrypt.hash_pwd_salt(password)

  def oauth_token_auth(jwt_token, _usage_info) do
    with {:ok, claims} <- JWT.verify_and_decode(jwt_token) do
      authenticate_oauth_claims(jwt_token, claims)
    else
      _ -> :error
    end
  end

  defp authenticate_oauth_claims(_jwt_token, %{"token_use" => "machine"} = claims) do
    with key_id when is_integer(key_id) <- Map.get(claims, "key_id"),
         scope when is_binary(scope) <- Map.get(claims, "scope"),
         scopes = String.split(scope, " ", trim: true),
         :ok <- Permissions.validate_scopes(scopes),
         subject when is_binary(subject) <- Map.get(claims, "sub"),
         {:ok, subject_type, subject_id} <- parse_subject(subject),
         {:ok, entity} <- load_entity(subject_type, subject_id),
         true <- validate_entity_auth(entity),
         %Key{} = key <- Keys.get(key_id),
         false <- Key.revoked?(key),
         true <- key_owner?(key, entity) do
      build_auth_result(entity, MachineToken.new(key, scopes))
    else
      _ -> :error
    end
  end

  defp authenticate_oauth_claims(jwt_token, claims) do
    if Map.has_key?(claims, "token_use") do
      :error
    else
      authenticate_persisted_oauth_token(jwt_token, claims)
    end
  end

  defp authenticate_persisted_oauth_token(jwt_token, claims) do
    with subject when is_binary(subject) <- Map.get(claims, "sub"),
         {:ok, subject_type, subject_id} <- parse_subject(subject),
         {:ok, entity} <- load_entity(subject_type, subject_id),
         true <- validate_entity_auth(entity),
         {:ok, oauth_token} <- Tokens.lookup(jwt_token, :access, preload: []) do
      build_auth_result(entity, oauth_token)
    else
      _ -> :error
    end
  end

  defp key_owner?(%Key{user_id: user_id}, %User{id: user_id}) when not is_nil(user_id), do: true

  defp key_owner?(%Key{organization_id: organization_id}, %Organization{id: organization_id})
       when not is_nil(organization_id),
       do: true

  defp key_owner?(_key, _entity), do: false

  defp parse_subject(subject) when is_binary(subject) do
    case String.split(subject, ":", parts: 2) do
      ["user", username] -> {:ok, :user, username}
      ["org", org_name] -> {:ok, :organization, org_name}
      _ -> {:error, :invalid_subject}
    end
  end

  defp load_entity(:user, username), do: load_user_from_username(username)
  defp load_entity(:organization, org_name), do: load_organization_from_name(org_name)

  defp validate_entity_auth(%User{} = user), do: user && not User.organization?(user)
  defp validate_entity_auth(%Organization{} = _organization), do: true

  defp build_auth_result(%User{} = user, oauth_token) do
    {:ok,
     %{
       auth_credential: oauth_token,
       user: user,
       organization: nil,
       email: find_email(user, nil)
     }}
  end

  defp build_auth_result(%Organization{} = organization, oauth_token) do
    {:ok,
     %{
       auth_credential: oauth_token,
       user: nil,
       organization: organization,
       email: nil
     }}
  end

  defp load_user_from_username(username) when is_binary(username) do
    case Users.get_by_username(username, [
           :emails,
           owned_packages: :repository,
           organizations: :repository
         ]) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp load_organization_from_name(org_name) when is_binary(org_name) do
    case Organizations.get(org_name, [
           :repository,
           :users
         ]) do
      nil -> {:error, :organization_not_found}
      organization -> {:ok, organization}
    end
  end

  def gen_key() do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp find_email(nil, _email) do
    nil
  end

  defp find_email(user, email) do
    Enum.find(user.emails, &(&1.email == email)) || Enum.find(user.emails, & &1.primary)
  end

  defp usage_info(info) do
    %{
      ip: parse_ip(info[:ip]),
      used_at: info[:used_at],
      user_agent: parse_user_agent(info[:user_agent])
    }
  end

  def provider_auth(provider, provider_uid) do
    user_provider =
      UserProviders.get_by_provider(provider, provider_uid,
        user: [:emails, owned_packages: :repository, organizations: :repository]
      )

    if user_provider && user_provider.user && not User.organization?(user_provider.user) do
      {:ok,
       %{
         auth_credential: nil,
         user: user_provider.user,
         organization: nil,
         email: find_email(user_provider.user, user_provider.provider_email)
       }}
    else
      :error
    end
  end
end

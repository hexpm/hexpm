defmodule Hexpm.Accounts.Auth do
  import Ecto.Query, only: [from: 2]

  alias Hexpm.Accounts.{Key, Keys, User, Users}
  alias Hexpm.OAuth.Token

  def key_auth(user_secret, usage_info) do
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    result =
      from(
        k in Key,
        where: k.secret_first == ^first,
        left_join: u in assoc(k, :user),
        left_join: o in assoc(k, :organization),
        preload: [user: {u, [:emails, owned_packages: :repository, organizations: :repository]}],
        preload: [organization: {o, [:repository, user: [:emails, owned_packages: :repository]]}]
      )
      |> Hexpm.Repo.one()

    case result do
      nil ->
        :error

      key ->
        valid_auth = !key.user || !User.organization?(key.user)

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
               email: find_email(key.user, nil)
             }}
          end
        else
          :error
        end
    end
  end

  def password_auth(username_or_email, password) do
    user =
      Users.get(username_or_email, [
        :emails,
        owned_packages: :repository,
        organizations: :repository
      ])

    valid_user = user && !User.organization?(user) && user.password

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

  def oauth_token_auth(user_token, _usage_info) do
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_token)
      |> Base.encode16(case: :lower)

    result =
      from(
        t in Token,
        where: t.token_first == ^first,
        left_join: u in User,
        on: t.user_id == u.id,
        preload: [user: {u, [:emails, owned_packages: :repository, organizations: :repository]}],
        select: {t, u}
      )
      |> Hexpm.Repo.one()

    case result do
      nil ->
        :error

      {oauth_token, user} ->
        valid_auth = user && !User.organization?(user)

        if valid_auth && Hexpm.Utils.secure_check(oauth_token.token_second, second) do
          if Token.valid?(oauth_token) do
            {:ok,
             %{
               auth_credential: oauth_token,
               user: user,
               organization: nil,
               email: find_email(user, nil)
             }}
          else
            :error
          end
        else
          :error
        end
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

  defp parse_ip(nil), do: nil

  defp parse_ip(ip_tuple) do
    ip_tuple
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp parse_user_agent(nil), do: nil
  defp parse_user_agent([]), do: nil
  defp parse_user_agent([value | _]), do: value
end

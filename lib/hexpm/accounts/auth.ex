defmodule Hexpm.Accounts.Auth do
  import Ecto.Query, only: [from: 2]

  alias Hexpm.Accounts.{Key, Users}

  def key_auth(user_secret, usage_info \\ %{}) do
    # Database index lookup on the first part of the key and then
    # secure compare on the second part to avoid timing attacks
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    result =
      from(
        k in Key,
        where: k.secret_first == ^first,
        join: u in assoc(k, :user),
        preload: [user: {u, [:owned_packages, :emails, :organizations]}]
      )
      |> Hexpm.Repo.one()

    case result do
      nil ->
        :error

      key ->
        if Hexpm.Utils.secure_check(key.secret_second, second) do
          if is_nil(key.revoked_at) do
            changeset = Key.usage_info_changeset(key, %{
              last_ip: usage_info[:ip],
              last_used_at: usage_info[:used_at],
              last_user_agent: usage_info[:user_agent],
              })
            Hexpm.Repo.update(changeset)
            {:ok, {key.user, key, find_email(key.user, nil), :key}}
          else
            :revoked
          end
        else
          :error
        end
    end
  end

  def password_auth(username_or_email, password) do
    user = Users.get(username_or_email, [:owned_packages, :emails, :organizations])

    if user && Bcrypt.verify_pass(password, user.password) do
      {:ok, {user, nil, find_email(user, username_or_email), :password}}
    else
      :error
    end
  end

  def gen_password(nil), do: nil
  def gen_password(password), do: Bcrypt.hash_pwd_salt(password)

  def gen_key() do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp find_email(user, email) do
    Enum.find(user.emails, &(&1.email == email)) || Enum.find(user.emails, & &1.primary)
  end
end

defmodule HexWeb.Auth do
  import Ecto.Query, only: [from: 2]

  def auth(user_secret) do
    # Database index lookup on the first part of the key and then
    # secure compare on the second part to avoid timing attacks
    app_secret = Application.get_env(:hex_web, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    result =
      from(k in HexWeb.Key,
           where: k.secret_first == ^first,
           join: u in assoc(k, :user),
           select: {u, k})
      |> HexWeb.Repo.one

    case result do
      {user, key} ->
        if Comeonin.Tools.secure_check(key.secret_second, second) do
          {:ok, user}
        else
          :error
        end
      nil ->
        :error
    end
  end
end

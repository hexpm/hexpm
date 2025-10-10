defmodule HexpmWeb.Session do
  alias Hexpm.Repo
  import Ecto.Query

  @behaviour Plug.Session.Store

  # Simple session schema for Plug session storage (CSRF, flash, etc)
  # This is separate from user authentication which uses user_sessions table
  defmodule PlugSession do
    use Ecto.Schema

    @timestamps_opts [type: :naive_datetime]

    schema "sessions" do
      field :token, :binary
      field :data, :map

      timestamps()
    end
  end

  def init(_opts) do
    :ok
  end

  def get(_conn, cookie, _opts) do
    with {id, "++" <> token} <- Integer.parse(cookie),
         {:ok, token} <- Base.url_decode64(token),
         session = Repo.get(PlugSession, id),
         true <- session && Plug.Crypto.secure_compare(token, session.token) do
      {{id, token}, session.data}
    else
      _ ->
        {nil, %{}}
    end
  end

  def put(_conn, nil, data, _opts) do
    token = :crypto.strong_rand_bytes(96)

    session =
      if Repo.write_mode?() do
        Repo.insert!(%PlugSession{token: token, data: data})
      else
        %PlugSession{id: 0, token: token, data: data}
      end

    build_cookie(session)
  end

  def put(_conn, {id, token}, data, _opts) do
    if Repo.write_mode?() do
      Repo.update_all(
        from(s in PlugSession, where: s.id == ^id),
        set: [
          data: data,
          updated_at: DateTime.utc_now()
        ]
      )
    end

    build_cookie(id, token)
  end

  def delete(_conn, {id, _token}, _opts) do
    if Repo.write_mode?() do
      Repo.delete_all(from(s in PlugSession, where: s.id == ^id))
    end

    :ok
  end

  defp build_cookie(session) do
    build_cookie(session.id, session.token)
  end

  defp build_cookie(id, token) do
    "#{id}++#{Base.url_encode64(token)}"
  end
end

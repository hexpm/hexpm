defmodule HexpmWeb.Session do
  alias Hexpm.Accounts.Session
  alias Hexpm.Repo

  @behaviour Plug.Session.Store

  def init(_opts) do
    :ok
  end

  def get(_conn, cookie, _opts) do
    with {id, "++" <> token} <- Integer.parse(cookie),
         {:ok, token} <- Base.url_decode64(token),
         session = Repo.get(Session, id),
         true <- session && Plug.Crypto.secure_compare(token, session.token) do
      {{id, token}, session.data}
    else
      _ ->
        {nil, %{}}
    end
  end

  def put(_conn, nil, data, _opts) do
    session = Session.build(data)

    session =
      if Repo.write_mode?() do
        Repo.insert!(session)
      else
        Ecto.Changeset.apply_changes(session)
      end

    build_cookie(session)
  end

  def put(_conn, {id, token}, data, _opts) do
    if Repo.write_mode?() do
      Repo.update_all(
        Session.by_id(id),
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
      Repo.delete_all(Session.by_id(id))
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

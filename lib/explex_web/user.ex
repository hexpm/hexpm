defmodule User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]

  queryable "users" do
    field :username, :string
    field :password, :string
    field :created, :datetime
  end

  def create(username, password) do
    password = String.to_char_list!(password)
    { :ok, salt } = :bcrypt.gen_salt()
    { :ok, hash } = :bcrypt.hashpw(password, salt)
    hash = :erlang.list_to_binary(hash)

    User.new(username: username, password: hash)
    |> ExplexWeb.Repo.create
  end

  def auth?(username, password) do
    stored_hash = ExplexWeb.Repo.all(
      from(u in User,
      where: u.username == ^username,
      select: u.password))

    case stored_hash do
      [stored_hash] ->
        password = String.to_char_list!(password)
        stored_hash = :erlang.binary_to_list(stored_hash)
        { :ok, hash } = :bcrypt.hashpw(password, stored_hash)
        hash == stored_hash
      [] ->
        false
    end
  end
end

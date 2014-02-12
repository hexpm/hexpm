defmodule ExplexWeb.User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import ExplexWeb.Util.Validation

  if Mix.env == :test do
    @password_work_factor 4
  else
    @password_work_factor 12
  end

  queryable "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    has_many :packages, ExplexWeb.Package, foreign_key: :owner_id
    field :created, :datetime
  end

  validate user,
    username: type(:string) and present(),
    email: type(:string) and present(),
    password: type(:string) and present(),
    also: unique([:username, :email], on: ExplexWeb.Repo)

  def create(username, email, password) do
    user = ExplexWeb.User.new(username: username, email: email, password: password)

    case validate(user) do
      [] ->
        password = String.to_char_list!(password)
        { :ok, salt } = :bcrypt.gen_salt(@password_work_factor)
        { :ok, hash } = :bcrypt.hashpw(password, salt)
        hash = :erlang.list_to_binary(hash)
        user = user.password(hash)

        { :ok, ExplexWeb.Repo.create(user) }
      errors ->
        { :error, errors }
    end
  end

  def get(username) do
    from(u in ExplexWeb.User, where: u.username == ^username)
    |> ExplexWeb.Repo.all
    |> List.first
  end

  def auth?(nil, _password), do: false

  def auth?(user, password) do
    stored_hash = user.password
    password = String.to_char_list!(password)
    stored_hash = :erlang.binary_to_list(stored_hash)
    { :ok, hash } = :bcrypt.hashpw(password, stored_hash)
    hash == stored_hash
  end
end

defimpl ExplexWeb.Render, for: ExplexWeb.User.Entity do
  import ExplexWeb.Util

  def render(user) do
    user.__entity__(:keywords)
    |> Dict.take([:username, :email, :created])
    |> Dict.update!(:created, &to_iso8601/1)
    |> Dict.put(:url, url(["users", user.username]))
  end
end

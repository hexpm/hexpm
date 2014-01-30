defmodule ExplexWeb.User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]

  queryable "users" do
    field :username, :string
    field :password, :string
    has_many :packages, ExplexWeb.Package, foreign_key: :owner_id
    field :created, :datetime
  end

  validate user,
    username: present()

  # Improves test running time
  # This depends on :build_per_environment
  # When we get :application.change_config_data we can remove this
  if Mix.env == :test do
    @work_factor 4
  else
    @work_factor 12
  end

  def create(username, password) do
    password = String.to_char_list!(password)
    { :ok, salt } = :bcrypt.gen_salt(@work_factor)
    { :ok, hash } = :bcrypt.hashpw(password, salt)
    hash = :erlang.list_to_binary(hash)

    user = ExplexWeb.User.new(username: username, password: hash)
    case validate(user) do
      [] -> { :ok, ExplexWeb.Repo.create(user) }
      errors -> { :error, errors }
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

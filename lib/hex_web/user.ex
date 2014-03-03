defmodule HexWeb.User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation

  queryable "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    has_many :packages, HexWeb.Package, foreign_key: :owner_id
    field :created, :datetime
  end

  validate user,
    username: present() and type(:string) and has_format(~r"^[a-z0-9_\-\.!~\*'\(\)]+$", message: "illegal characters"),
    email: present() and type(:string) and has_format(~r"^.+@.+\..+$"),
    password: present() and type(:string) and has_format(~r"[^'!:@\"]+", message: "illegal characters: '!:@\""),
    also: unique([:username], on: HexWeb.Repo, case_sensitive: false),
    also: unique([:email], on: HexWeb.Repo)

  def create(username, email, password) do
    username = if is_binary(username), do: String.downcase(username), else: username
    email = if is_binary(email), do: String.downcase(email), else: email
    user = HexWeb.User.new(username: username, email: email, password: password)

    case validate(user) do
      [] ->
        password      = String.to_char_list!(password)
        work_factor   = HexWeb.Config.password_work_factor
        { :ok, salt } = :bcrypt.gen_salt(work_factor)
        { :ok, hash } = :bcrypt.hashpw(password, salt)
        hash          = :erlang.list_to_binary(hash)
        user          = user.password(hash)

        { :ok, HexWeb.Repo.create(user) }
      errors ->
        { :error, errors }
    end
  end

  def get(username) do
    from(u in HexWeb.User, where: downcase(u.username) == downcase(^username))
    |> HexWeb.Repo.all
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

defimpl HexWeb.Render, for: HexWeb.User.Entity do
  import HexWeb.Util

  def render(user) do
    user.__entity__(:keywords)
    |> Dict.take([:username, :email, :created])
    |> Dict.update!(:created, &to_iso8601/1)
    |> Dict.put(:url, api_url(["users", user.username]))
  end
end

defmodule Hexpm.OAuth.AuthorizationCode do
  use Hexpm.Schema

  alias Hexpm.Accounts.User
  alias Hexpm.Permissions

  schema "authorization_codes" do
    field :code, :string
    field :redirect_uri, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :code_challenge, :string
    field :code_challenge_method, :string

    belongs_to :user, User
    belongs_to :client, Hexpm.OAuth.Client, references: :client_id, type: :binary_id

    timestamps()
  end

  @valid_challenge_methods ~w(S256)

  def changeset(auth_code, attrs) do
    auth_code
    |> cast(attrs, [
      :code,
      :redirect_uri,
      :scopes,
      :expires_at,
      :used_at,
      :code_challenge,
      :code_challenge_method,
      :user_id,
      :client_id
    ])
    |> validate_required([
      :code,
      :redirect_uri,
      :scopes,
      :expires_at,
      :user_id,
      :client_id,
      :code_challenge,
      :code_challenge_method
    ])
    |> validate_scopes()
    |> validate_code_challenge()
    |> unique_constraint(:code)
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  def mark_as_used(%__MODULE__{} = auth_code) do
    changeset(auth_code, %{used_at: DateTime.utc_now()})
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      case Permissions.validate_scopes(scopes) do
        :ok -> []
        {:error, message} -> [scopes: message]
      end
    end)
  end

  defp validate_code_challenge(changeset) do
    code_challenge_method = get_field(changeset, :code_challenge_method)

    if not is_nil(code_challenge_method) and code_challenge_method not in @valid_challenge_methods do
      add_error(
        changeset,
        :code_challenge_method,
        "must be one of: #{Enum.join(@valid_challenge_methods, ", ")}"
      )
    else
      changeset
    end
  end
end

defmodule Hexpm.UserSession do
  use Hexpm.Schema

  alias Hexpm.Accounts.User
  alias Hexpm.OAuth.{Client, Token}

  @types ~w(browser oauth)

  schema "user_sessions" do
    field :type, :string
    field :name, :string
    field :revoked_at, :utc_datetime_usec

    embeds_one :last_use, Use, on_replace: :delete do
      field :used_at, :utc_datetime_usec
      field :user_agent, :string
      field :ip, :string
    end

    # Browser-specific fields
    field :session_token, :binary

    # OAuth-specific fields
    belongs_to :client, Client, references: :client_id, type: :binary_id

    belongs_to :user, User
    has_many :tokens, Token, foreign_key: :user_session_id

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:type, :name, :revoked_at, :user_id, :client_id, :session_token])
    |> validate_required([:type, :user_id])
    |> validate_inclusion(:type, @types)
    |> validate_type_specific_fields()
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  def update_last_use(session, params) do
    session
    |> change()
    |> put_embed(:last_use, struct(__MODULE__.Use, params))
  end

  defp validate_type_specific_fields(changeset) do
    type = get_field(changeset, :type)

    case type do
      "browser" ->
        changeset
        |> validate_required([:session_token])
        |> validate_nil_field(:client_id, "must be nil for browser sessions")

      "oauth" ->
        changeset
        |> validate_required([:client_id])
        |> validate_nil_field(:session_token, "must be nil for oauth sessions")

      _ ->
        changeset
    end
  end

  defp validate_nil_field(changeset, field, message) do
    if get_field(changeset, field) != nil do
      add_error(changeset, field, message)
    else
      changeset
    end
  end

  def browser?(session), do: session.type == "browser"
  def oauth?(session), do: session.type == "oauth"
  def revoked?(session), do: session.revoked_at != nil
end

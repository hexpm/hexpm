defmodule Hexpm.OAuth.Session do
  use Hexpm.Schema

  alias Hexpm.Accounts.User
  alias Hexpm.OAuth.{Client, Token}

  schema "oauth_sessions" do
    field :name, :string
    field :revoked_at, :utc_datetime_usec

    embeds_one :last_use, Use, on_replace: :delete do
      field :used_at, :utc_datetime_usec
      field :user_agent, :string
      field :ip, :string
    end

    belongs_to :user, User
    belongs_to :client, Client, references: :client_id, type: :binary_id
    has_many :tokens, Token, foreign_key: :session_id

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:name, :revoked_at, :user_id, :client_id])
    |> validate_required([:user_id, :client_id])
    |> cast_embed(:last_use)
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end
end

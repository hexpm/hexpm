defmodule Hexpm.Accounts.UserProvider do
  use Hexpm.Schema

  schema "user_providers" do
    field :provider, :string
    field :provider_uid, :string
    field :provider_email, :string
    field :provider_data, :map, default: %{}

    belongs_to :user, User

    timestamps()
  end

  def changeset(user_provider, params) do
    cast(user_provider, params, ~w(provider provider_uid provider_email provider_data)a)
    |> validate_required(~w(provider provider_uid)a)
    |> validate_inclusion(:provider, ~w(github))
    |> unique_constraint([:provider, :provider_uid])
  end

  def build(user, provider, provider_uid, provider_email, provider_data \\ %{}) do
    %__MODULE__{
      user_id: user.id,
      provider: provider,
      provider_uid: provider_uid,
      provider_email: provider_email,
      provider_data: provider_data
    }
  end
end

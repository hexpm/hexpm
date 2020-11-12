defmodule Hexpm.Accounts.SingleUseToken do
  use Hexpm.Schema

  @token_size 24
  @allowed_types ["github_merge_token"]

  schema "single_use_tokens" do
    field :token, :string
    field :type, :string
    field :payload, :map
    field :used?, :boolean, default: false
  end

  def changeset(type, payload) do
    %__MODULE__{}
    |> cast(%{type: type, payload: payload}, [:type, :payload])
    |> validate_required([:type, :payload])
    |> validate_inclusion(:type, @allowed_types)
    |> put_token()
  end

  def set_used(token), do: change(token, used?: true)

  defp put_token(changeset), do: put_change(changeset, :token, random_token())

  defp random_token do
    @token_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end

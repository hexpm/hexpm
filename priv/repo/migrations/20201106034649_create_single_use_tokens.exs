defmodule Hexpm.RepoBase.Migrations.CreateSingleUseTokens do
  use Ecto.Migration

  def change do
    create table(:single_use_tokens) do
      add(:token, :string)
      add(:type, :string)
      add(:payload, :map)
      add(:used?, :boolean)
    end
  end
end

defmodule Hexpm.Accounts.GitHubAccount do
  use Hexpm.Schema

  alias Hexpm.Accounts.User

  schema "github_accounts" do
    field :github_user_id, :integer

    belongs_to :user, User
  end

  def build(user_id, github_user_id) do
    %__MODULE__{}
    |> cast(%{user_id: user_id, github_user_id: github_user_id}, [:user_id, :github_user_id])
    |> validate_required([:user_id, :github_user_id])
  end
end

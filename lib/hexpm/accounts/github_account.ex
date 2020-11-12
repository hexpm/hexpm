defmodule Hexpm.Accounts.GitHubAccount do
  use Hexpm.Schema

  alias Hexpm.Accounts.User

  schema "github_accounts" do
    field :github_user_id, :integer

    belongs_to :user, User
  end

  def build(user, github_user_id) do
    user
    |> Ecto.build_assoc(:github_account)
    |> cast(%{github_user_id: github_user_id}, [:github_user_id])
    |> validate_required([:github_user_id])
  end
end

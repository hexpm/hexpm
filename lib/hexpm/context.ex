defmodule Hexpm.Context do
  defmacro __using__(_opts) do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]

      import Hexpm.Accounts.AuditLog,
        only: [audit: 3, audit: 4, audit_many: 4, audit_with_user: 4]

      alias Ecto.Multi
      alias Hexpm.Repo

      use Hexpm.Shared
    end
  end
end

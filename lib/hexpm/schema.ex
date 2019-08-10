defmodule Hexpm.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      @timestamps_opts [type: :utc_datetime_usec]

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Hexpm.Changeset

      alias Ecto.Multi

      use Hexpm.Shared
    end
  end
end

defmodule HexWeb.Timestamps do

  # From Ecto.Model.Timestamps

  defmacro __using__(_) do
    quote do
      before_insert HexWeb.Timestamps, :put_timestamp, [:inserted_at]

      before_insert HexWeb.Timestamps, :put_timestamp, [:updated_at]
      before_update HexWeb.Timestamps, :put_timestamp, [:updated_at]
    end
  end

  import Ecto.Changeset

  def put_timestamp(changeset, field) do
    if get_change changeset, field do
      changeset
    else
      value = HexWeb.Util.type_load!(HexWeb.DateTime, timestamp_tuple())
      put_change changeset, field, value
    end
  end

  defp timestamp_tuple do
    :os.timestamp
    |> :calendar.now_to_datetime
  end
end

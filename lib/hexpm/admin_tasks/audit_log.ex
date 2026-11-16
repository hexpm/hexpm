defmodule Hexpm.AdminTasks.AuditLog do
  @moduledoc """
  One run of a task in `Hexpm.AdminTasks`, whether it came from the admin
  dashboard, the console or a background job.

  `user_data` keeps the id and username of the moderator who ran it, so the
  entry still names them after their account is deleted. A console run has no
  user and the user agent `"CONSOLE"`.

  The entry is inserted as `"started"` before the task runs. `status` then
  becomes `"ok"` or `"error"` from the task's return value, or `"raised"` when
  it raised, and `result` holds the error or a short summary of what it
  returned. An entry still `"started"` is a run that never finished.
  """

  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "admin_audit_logs" do
    field :user_data, :map
    field :action, :string
    field :params, :map
    field :status, :string
    field :result, :string
    field :user_agent, :string
    field :remote_ip, :string
    field :request_id, :string

    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def build(audit_data, action, params) do
    user =
      case audit_data.user do
        %User{organization_id: nil} = user -> user
        _other -> nil
      end

    %__MODULE__{
      user_id: user && user.id,
      user_data: user && %{id: user.id, username: user.username},
      action: Atom.to_string(action),
      params: params,
      status: "started",
      user_agent: audit_data.user_agent && Hexpm.Utils.truncate_bytes(audit_data.user_agent, 255),
      remote_ip: audit_data.remote_ip,
      request_id: Map.get(audit_data, :request_id)
    }
  end

  def newest_first() do
    from(l in __MODULE__, order_by: [desc: l.inserted_at, desc: l.id])
  end
end

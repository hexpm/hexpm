defmodule Hexpm.Accounts.TwoFactor do
  use Hexpm.Web, :schema

  schema "twofactor" do
    field :type, :string, default: "disabled"
    field :enabled, :boolean, default: false
    field :data, :map, default: %{}

    belongs_to :user, User

    timestamps()
  end

  def enabled?(nil), do: false
  def enabled?(twofactor), do: twofactor.enabled

  def changeset(twofactor, _params) do
    change(twofactor)
  end

  def toggle_enabled(twofactor, _params, flag) do
    change(twofactor, %{enabled: flag})
  end

  def setup(twofactor, _params, :totp) do
    secret = TOTP.generate_key() |> TOTP.encrypt_secret()
    codes  = BackupCode.generate(10) |> BackupCode.encrypt()
    data   = %{secret: secret, backupcodes: codes}

    change(twofactor, %{type: "totp", data: data})
  end

  def set_last(twofactor, _params, code) do
    data = Map.put(twofactor.data, "last", code)

    change(twofactor, %{data: data})
  end

  def regen_backupcodes(twofactor, _params) do
    new  = BackupCode.generate(10) |> BackupCode.encrypt()
    data = Map.put(twofactor.data, "backupcodes", new)

    change(twofactor, %{data: data})
  end

  def use_backupcode(twofactor, _params, code) do
    new =
      BackupCode.decrypt(twofactor.data["backupcodes"])
      |> List.delete(code)
      |> BackupCode.encrypt()

    data = Map.put(twofactor.data, "backupcodes", new)

    change(twofactor, %{data: data})
  end
end

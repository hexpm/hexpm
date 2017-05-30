defmodule Hexpm.Accounts.UserTwoFactor do
  use Hexpm.Web, :schema

  @types ~w(totp disabled)

  embedded_schema do
    field :enabled, :boolean, default: false
    field :type, :string, default: "disabled"
    field :secret, :string, default: ""
    field :backupcodes, {:array, :string}, default: []
  end

  def setup(twofactor, params) do
    secret = TOTP.generate_key() |> TOTP.encrypt_secret()
    codes  = BackupCode.generate(10) |> BackupCode.encrypt()

    cast(twofactor, params, ~w(type))
    |> put_change(:secret, secret)
    |> put_change(:backupcodes, codes)
    |> validate_inclusion(:type, @types)
  end

  def enable(twofactor, _params) do
    change(twofactor)
    |> put_change(:enabled, true)
  end

  def disable(twofactor, _params) do
    change(twofactor)
    |> put_change(:enabled, false)
    |> put_change(:secret, "")
    |> put_change(:backupcodes, [])
    |> put_change(:type, "disabled")
  end

  def regen_backup_codes(twofactor, _params) do
    codes = BackupCode.generate(10) |> BackupCode.encrypt()

    change(twofactor)
    |> put_change(:backupcodes, codes)
  end

  def use_backup_code(twofactor, params) do
    cast(twofactor, params, ~w(backupcodes))
  end
end

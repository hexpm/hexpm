defmodule Hexpm.Accounts.TOTP do
  alias Hexpm.Accounts.BackupCode

  @app_secret Application.get_env(:hexpm, :totp_encryption_secret)
  @enc_tag "HEXTOTPSECRET"

  @moduledoc """
  Defines a `Hexpm.Accounts.TOTP` struct.

  The following fields are public:
    * `issuer`        - The application name that appears in Google Authenticator. (default: "Hex")
    * `account_name`  - The username that appears in Google Authenticator.
    * `key`           - A shared, base32 encoded secret of arbitrary length.
    * `interval`      - Defines a period that a TOTP code will be valid for, in seconds. (default: 30)
    * `digits`        - The number of digits that are present in the code. (default: 6)
    * `backupcodes`   - An array of backup codes to test (default: [])
  """

  defstruct issuer: "Hex.pm",
            account_name: "",
            key: "",
            interval: 30,
            digits: 6

  @doc """
  Returns a new %TOTP{} struct
  """
  def new(params \\ []), do: struct(__MODULE__, params)

  @doc """
  Returns a new %TOTP{} struct with a decrypted `key`
  """
  def new_encrypted(params \\ []) do
    params = Keyword.update(params, :key, "", fn enc ->
      decrypt_secret(enc)
    end)

    params = Keyword.update(params, :backupcodes, [], fn enc ->
      Enum.map(enc, fn enc ->
        BackupCode.decrypt(enc)
      end)
    end)

    struct(__MODULE__, params)
  end

  @doc """
  Generate a Base32 encoded key of 20 bits.
  """
  def generate_key, do: :crypto.strong_rand_bytes(20) |> Base.encode32(case: :lower)

  @doc """
  Generate a Key URI to create a QR Code for Google Authenticator given a %TOTP{} struct `t`.
  """
  def token(t) do
    "otpauth://totp/#{t.issuer}:#{t.account_name}?secret=#{t.key}&issuer=#{t.issuer}&digits=#{t.digits}&interval=#{t.interval}"
  end

  @doc """
  Generate a PNG QR code from the Google Autentication token given a %TOTP{} struct `t` in Base64.
  """
  def qrcode(t) do
    token(t)
    |> :qrcode.encode
    |> :qrcode_demo.simple_png_encode
    |> Base.encode64
  end

  @doc """
  Generate a TOTP code given a %TOTP{} struct `t`.

  Used for testing.
  """
  def code(t) do
    options = [interval_length: t.interval, token_length: t.digits]
    code = Comeonin.Otp.gen_totp(String.upcase(t.key), options)

    {code, t.interval}
  end

  @doc """
  Verify a TOTP code given a %TOTP{} struct `t` and a candidate code `code`

  There is one option:
    * window - the number of attempts, before and after the current one, allowed
      * the default is 1 (1 interval before and 1 interval after)
      * used take into account clock skew
  """
  def verify(t, code, opts \\ []) do
    window = Keyword.get(opts, :window, 1)

    options = [
      interval_length: t.interval,
      window: window,
      token_length: t.digits
    ]

    case Comeonin.Otp.check_totp(code, String.upcase(t.key), options) do
      true ->
        true

      x when is_number(x) ->
        # when the current code is in the previous or next window, the timestamp
        # is returned instead of a boolean value
        true

      _ ->
        if BackupCode.is?(code) do
          {:backupcode, code}
        else
          false
        end
    end
  end

  def encrypt_secret(secret) do
    Hexpm.Crypto.encrypt(secret, @app_secret, @enc_tag)
  end

  def decrypt_secret(encrypted) do
    {:ok, secret} = Hexpm.Crypto.decrypt(encrypted, @app_secret, @enc_tag)
    secret
  end
end

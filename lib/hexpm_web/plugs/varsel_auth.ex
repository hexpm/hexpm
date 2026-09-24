defmodule HexpmWeb.Plugs.VarselAuth do
  @behaviour Plug

  import Plug.Conn
  import HexpmWeb.ControllerHelpers, only: [render_error: 3]

  alias HexpmWeb.Plugs.Attack

  @issuer "varsel"
  @max_lifetime 300

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    keys = keys()

    with {:ok, token} <- bearer(conn),
         {:ok, _claims} <- verify(token, keys) do
      conn
    else
      {:error, _reason} -> refuse(conn)
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _other -> {:error, :missing_token}
    end
  end

  defp keys do
    %{"keys" => keys} =
      Application.fetch_env!(:hexpm, :varsel)
      |> Keyword.fetch!(:jwks)
      |> JSON.decode!()

    Map.new(keys, &{&1["kid"], &1})
  end

  defp verify(token, keys) do
    with {:ok, kid} <- kid(token),
         {:ok, jwk} <- key(keys, kid),
         {:ok, claims} <- signature(token, jwk),
         :ok <- identity(claims),
         :ok <- validity(claims) do
      consume(claims)
    end
  rescue
    _error -> {:error, :malformed_token}
  end

  defp kid(token) do
    case Joken.peek_header(token) do
      {:ok, %{"alg" => "ES256", "kid" => kid}} when is_binary(kid) -> {:ok, kid}
      _other -> {:error, :malformed_header}
    end
  end

  defp key(keys, kid) do
    case Map.fetch(keys, kid) do
      {:ok, jwk} -> {:ok, jwk}
      :error -> {:error, :unknown_key}
    end
  end

  defp signature(token, jwk) do
    case Joken.Signer.verify(token, Joken.Signer.create("ES256", jwk)) do
      {:ok, claims} -> {:ok, claims}
      {:error, _reason} -> {:error, :bad_signature}
    end
  end

  defp identity(claims) do
    cond do
      claims["iss"] != @issuer -> {:error, :bad_issuer}
      claims["sub"] != @issuer -> {:error, :bad_subject}
      not audience?(claims["aud"]) -> {:error, :bad_audience}
      not is_binary(claims["jti"]) -> {:error, :missing_jti}
      true -> :ok
    end
  end

  defp audience?(aud) when is_list(aud), do: HexpmWeb.Endpoint.url() in aud
  defp audience?(aud), do: aud == HexpmWeb.Endpoint.url()

  defp validity(claims) do
    now = System.system_time(:second)
    exp = claims["exp"]
    nbf = claims["nbf"]
    iat = if is_integer(claims["iat"]), do: claims["iat"], else: now

    cond do
      not is_integer(exp) -> {:error, :missing_expiry}
      exp <= now -> {:error, :expired}
      is_integer(nbf) and nbf > now -> {:error, :not_yet_valid}
      exp - iat > @max_lifetime -> {:error, :lifetime_too_long}
      true -> :ok
    end
  end

  defp consume(%{"jti" => jti} = claims) do
    if Attack.varsel_jti(jti) == 1, do: {:ok, claims}, else: {:error, :replayed}
  end

  defp refuse(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer error="invalid_token"))
    |> render_error(401, message: "invalid token")
  end
end

defmodule Hexpm.Accounts.SSO.SafeURL do
  import Bitwise

  alias Hexpm.Accounts.SSO.Error

  @dns_timeout 5_000
  @public_ipv6_prefix {{0x2000, 0, 0, 0, 0, 0, 0, 0}, 3}
  @non_public_ipv6_prefixes [
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23},
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0x3FFE, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20}
  ]

  def validate(value) do
    with {:ok, uri, _addresses} <- resolve(value) do
      {:ok, uri}
    end
  end

  def resolve(value) do
    with {:ok, uri} <- validate_syntax(value),
         {:ok, addresses} <- validated_addresses(uri.host) do
      {:ok, uri, addresses}
    end
  end

  def validate_syntax(value) when is_binary(value) do
    uri = URI.parse(value)

    cond do
      uri.scheme != "https" -> error(:https_required)
      is_nil(uri.host) or uri.host == "" -> error(:host_required)
      uri.userinfo -> error(:userinfo_not_allowed)
      uri.fragment -> error(:fragment_not_allowed)
      true -> {:ok, uri}
    end
  end

  def validate_syntax(_value), do: error(:invalid_url)

  defp validated_addresses(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> validate_public_addresses([address])
      {:error, :einval} -> resolve_and_validate(host)
    end
  end

  defp resolve_and_validate(host) do
    task =
      Task.Supervisor.async_nolink(Hexpm.Tasks, fn ->
        [:inet, :inet6]
        |> Enum.flat_map(fn family ->
          case resolver().getaddrs(String.to_charlist(host), family) do
            {:ok, addresses} -> addresses
            {:error, _reason} -> []
          end
        end)
        |> Enum.uniq()
      end)

    case Task.yield(task, dns_timeout()) do
      {:ok, []} ->
        error(:dns_resolution_failed)

      {:ok, addresses} ->
        validate_public_addresses(addresses)

      {:exit, _reason} ->
        error(:dns_resolution_failed)

      nil ->
        Task.shutdown(task, :brutal_kill)
        error(:dns_resolution_timeout)
    end
  end

  defp resolver do
    Application.get_env(:hexpm, :sso_dns_resolver, __MODULE__.Resolver)
  end

  defp dns_timeout do
    Application.get_env(:hexpm, :sso_dns_timeout, @dns_timeout)
  end

  defp validate_public_addresses(addresses) do
    if Enum.all?(addresses, &public_address?/1) do
      {:ok, addresses}
    else
      error(:private_address_not_allowed)
    end
  end

  defp public_address?({a, b, c, _d}) do
    not (a in [0, 10, 127] or
           (a == 100 and b in 64..127) or
           (a == 169 and b == 254) or
           (a == 172 and b in 16..31) or
           (a == 192 and b == 0) or
           (a == 192 and b == 168) or
           (a == 192 and b == 88 and c == 99) or
           (a == 198 and b in 18..19) or
           (a == 198 and b == 51 and c == 100) or
           (a == 203 and b == 0 and c == 113) or
           a >= 224)
  end

  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    public_address?({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})
  end

  defp public_address?({0, 0, 0, 0, 0, 0, _high, _low}), do: false

  defp public_address?({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    in_ipv6_prefix?(address, @public_ipv6_prefix) and
      Enum.all?(@non_public_ipv6_prefixes, fn prefix ->
        not in_ipv6_prefix?(address, prefix)
      end)
  end

  defp in_ipv6_prefix?(address, {prefix, prefix_length}) do
    shift = 128 - prefix_length
    ipv6_to_integer(address) >>> shift == ipv6_to_integer(prefix) >>> shift
  end

  defp ipv6_to_integer(address) do
    address
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> acc <<< 16 ||| part end)
  end

  defp error(code), do: {:error, %Error{stage: :url_validation, code: code}}
end

defmodule Hexpm.Accounts.SSO.SafeURL.Resolver do
  def getaddrs(host, family), do: :inet.getaddrs(host, family)
end

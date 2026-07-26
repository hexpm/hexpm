defmodule Hexpm.Accounts.SSO.DomainName do
  @label_regex ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  @challenge_prefix "_hexpm-sso."
  @max_domain_length 253 - byte_size(@challenge_prefix)

  def canonicalize(value) when is_binary(value) do
    if String.valid?(value), do: do_canonicalize(value), else: {:error, :invalid_domain}
  end

  def canonicalize(_value), do: {:error, :invalid_domain}

  defp do_canonicalize(value) do
    value =
      value
      |> String.trim()
      |> strip_trailing_dot()
      |> String.downcase()

    with true <- value != "",
         false <- String.contains?(value, "*"),
         false <- String.starts_with?(value, "."),
         false <- String.ends_with?(value, "."),
         false <- String.contains?(value, ".."),
         {:error, :einval} <- :inet.parse_address(String.to_charlist(value)),
         {:ok, ascii} <- to_ascii(value),
         :ok <- validate_ascii(ascii),
         :ok <- reject_public_suffix(ascii) do
      {:ok, ascii}
    else
      _other -> {:error, :invalid_domain}
    end
  end

  def from_email(value) when is_binary(value) and byte_size(value) <= 320 do
    if String.valid?(value) do
      case String.split(value, "@") do
        [local, domain] when local != "" and domain != "" -> canonicalize(domain)
        _other -> {:error, :invalid_email}
      end
    else
      {:error, :invalid_email}
    end
  end

  def from_email(_value), do: {:error, :invalid_email}

  defp strip_trailing_dot(value) do
    if String.ends_with?(value, ".") do
      binary_part(value, 0, byte_size(value) - 1)
    else
      value
    end
  end

  defp to_ascii(value) do
    ascii =
      value
      |> String.to_charlist()
      |> :idna.encode([:uts46, :std3_rules, :strict])
      |> List.to_string()
      |> String.downcase()

    {:ok, ascii}
  rescue
    _exception -> {:error, :invalid_domain}
  catch
    :exit, _reason -> {:error, :invalid_domain}
  end

  defp validate_ascii(ascii) do
    labels = String.split(ascii, ".")

    if byte_size(ascii) <= @max_domain_length and length(labels) >= 2 and
         Enum.all?(labels, &(byte_size(&1) <= 63 and Regex.match?(@label_regex, &1))) do
      :ok
    else
      {:error, :invalid_domain}
    end
  end

  defp reject_public_suffix(ascii) do
    unicode =
      ascii
      |> String.to_charlist()
      |> :idna.decode([:uts46, :std3_rules, :strict])
      |> List.to_string()

    case Domainatrex.parse(unicode) do
      {:ok, %{domain: domain}} when is_binary(domain) and domain != "" ->
        if Domainatrex.tld?(unicode), do: {:error, :public_suffix}, else: :ok

      _other ->
        {:error, :public_suffix}
    end
  rescue
    _exception -> {:error, :invalid_domain}
  catch
    :exit, _reason -> {:error, :invalid_domain}
  end
end

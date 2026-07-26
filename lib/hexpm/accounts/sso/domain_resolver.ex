defmodule Hexpm.Accounts.SSO.DomainResolver do
  @type result ::
          {:ok, [String.t()]}
          | {:transient, atom()}
          | {:definitive, atom()}

  @callback lookup_txt(String.t()) :: result()

  def impl do
    Application.fetch_env!(:hexpm, :organization_sso)
    |> Keyword.fetch!(:domain_resolver)
  end
end

defmodule Hexpm.Accounts.SSO.DomainResolver.Inet do
  @behaviour Hexpm.Accounts.SSO.DomainResolver

  @timeout 5_000

  @doc false
  def timeout_ms, do: @timeout

  @impl true
  def lookup_txt(name), do: lookup_txt(name, &:inet_res.resolve/5)

  @doc false
  def lookup_txt(name, resolver) when is_function(resolver, 5) do
    case resolver.(String.to_charlist(name), :in, :txt, [], @timeout) do
      {:ok, message} ->
        with {:ok, answers} <- answer_records(message),
             {:ok, records} <- normalize_answers(answers) do
          if records == [], do: {:definitive, :missing}, else: {:ok, records}
        else
          :error -> {:definitive, :malformed}
        end

      {:error, :nxdomain} ->
        {:definitive, :missing}

      {:error, {:nxdomain, _message}} ->
        {:definitive, :missing}

      {:error, {reason, _message}} ->
        {:transient, reason}

      {:error, reason} ->
        {:transient, reason}
    end
  rescue
    _exception -> {:transient, :resolver_failure}
  end

  defp answer_records(message) do
    {:ok, :inet_dns.msg(message, :anlist)}
  rescue
    _exception -> :error
  end

  defp normalize_answers(answers) do
    answers
    |> Enum.reduce_while({:ok, []}, fn answer, {:ok, records} ->
      case normalize_answer(answer) do
        :skip -> {:cont, {:ok, records}}
        {:ok, record} -> {:cont, {:ok, [record | records]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      :error -> :error
    end
  end

  defp normalize_answer(answer) do
    case :inet_dns.rr(answer, :type) do
      :txt -> normalize_txt(:inet_dns.rr(answer, :data))
      _other -> :skip
    end
  rescue
    _exception -> :error
  end

  defp normalize_txt(value) when is_list(value) do
    {:ok, IO.iodata_to_binary(value)}
  rescue
    _exception -> :error
  end

  defp normalize_txt(_value), do: :error
end

defmodule Hexpm.Accounts.SSO.OIDC.Issuer do
  alias Hexpm.Accounts.SSO.{Error, SafeURL}

  def validate(value) do
    with {:ok, uri} <- validate_syntax(value),
         {:ok, _uri, _addresses} <- SafeURL.resolve(value) do
      {:ok, uri}
    end
  end

  def validate_syntax(value) do
    with {:ok, uri} <- SafeURL.validate_syntax(value),
         :ok <- reject_query(uri) do
      {:ok, uri}
    end
  end

  defp reject_query(%URI{query: nil}), do: :ok
  defp reject_query(%URI{}), do: error(:query_not_allowed)

  defp error(code), do: {:error, %Error{stage: :url_validation, code: code}}
end

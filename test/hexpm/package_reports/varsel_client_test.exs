defmodule Hexpm.PackageReports.Varsel.ClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Hexpm.PackageReports.Varsel.Client

  @report_url "https://cna.erlef.org/api/hex/reports"

  setup :verify_on_exit!

  setup do
    original = Application.fetch_env!(:hexpm, :varsel)

    Application.put_env(
      :hexpm,
      :varsel,
      original
      |> Keyword.put(:report_url, @report_url)
      |> Keyword.put(:audience, @report_url)
      |> Keyword.put(:key_id, "hexpm-test")
    )

    on_exit(fn -> Application.put_env(:hexpm, :varsel, original) end)
  end

  test "posts the issue 94 JSON contract with a short-lived ES256 JWT" do
    report = report()
    report_url = "https://cna.erlef.org/reports/019a"
    sign_in_url = "https://cna.erlef.org/sign-in/hex?return-url=/reports/019a"

    expect(Hexpm.HTTP.Mock, :post, fn url, headers, body, opts ->
      assert url == @report_url
      assert JSON.decode!(body) == stringify_keys(report)
      assert {"accept", "application/json"} in headers
      assert {"content-type", "application/json"} in headers

      assert {"authorization", "Bearer " <> token} =
               List.keyfind(headers, "authorization", 0)

      assert {:ok, claims} = Joken.peek_claims(token)
      assert claims["iss"] == "hexpm"
      assert claims["sub"] == "hexpm"
      assert claims["aud"] == @report_url
      assert claims["exp"] - claims["iat"] == 60
      assert claims["nbf"] == claims["iat"] - 5
      assert is_binary(claims["jti"])

      signer =
        Joken.Signer.create(
          "ES256",
          %{"pem" => Application.fetch_env!(:hexpm, :jwt_signing_key)}
        )

      assert {:ok, ^claims} = Joken.Signer.verify(token, signer)

      [encoded_header | _] = String.split(token, ".")

      header =
        encoded_header
        |> Base.url_decode64!(padding: false)
        |> JSON.decode!()

      assert header["alg"] == "ES256"
      assert header["kid"] == "hexpm-test"

      assert opts == [
               receive_timeout: 15_000,
               request_timeout: 15_000,
               max_body_bytes: 32_000
             ]

      {:ok, 201, [{"location", report_url}],
       %{"id" => "019a", "url" => report_url, "sign_in_url" => sign_in_url}}
    end)

    assert Client.submit(report) ==
             {:ok, %{id: "019a", url: report_url, sign_in_url: sign_in_url}}
  end

  test "does not retry a rejected submission" do
    expect(Hexpm.HTTP.Mock, :post, 1, fn _url, _headers, _body, _opts ->
      {:ok, 503, [], %{"error" => "unavailable"}}
    end)

    log = capture_log(fn -> assert Client.submit(report()) == {:error, :unavailable} end)
    assert log =~ "Varsel package report submission failed"
  end

  test "rejects report links outside the configured Varsel origin" do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 201, [{"location", "https://example.com/reports/019a"}],
       %{
         "id" => "019a",
         "url" => "https://example.com/reports/019a",
         "sign_in_url" => "https://example.com/sign-in"
       }}
    end)

    assert capture_log(fn -> Client.submit(report()) end) =~ "invalid_response"
  end

  defp report do
    %{
      summary: "Unsafe parsing",
      description: "A crafted document can execute code.",
      package: "reported_package",
      maintainers: [
        %{name: "Maintainer", username: "maintainer", email: "maintainer@example.com"}
      ],
      reporter: %{name: "Reporter", username: "reporter", email: "reporter@example.com"}
    }
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end

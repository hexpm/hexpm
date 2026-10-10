defmodule Hexpm.Billing.HexpmAuthTest do
  # Sync: the token path is application environment every billing call reads.
  use ExUnit.Case, async: false
  import Mox

  @moduletag :tmp_dir

  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "token")
    File.write!(path, "first-token")

    Application.put_env(:hexpm, :billing_token_path, path)
    on_exit(fn -> Application.delete_env(:hexpm, :billing_token_path) end)

    %{path: path}
  end

  defp assert_token(headers, token) do
    assert List.keyfind(headers, "authorization", 0) == {"authorization", "Bearer " <> token}
  end

  test "sends the service account token on every kind of request" do
    expect(Hexpm.HTTP.Mock, :post, fn _url, headers, _body, _opts ->
      assert_token(headers, "first-token")
      {:ok, 204, [], ""}
    end)

    expect(Hexpm.HTTP.Mock, :patch, fn _url, headers, _body, _opts ->
      assert_token(headers, "first-token")
      {:ok, 200, [], %{}}
    end)

    expect(Hexpm.HTTP.Mock, :get, 2, fn url, headers, _opts ->
      assert_token(headers, "first-token")

      if url =~ "/html" do
        {:ok, 200, [], "<html></html>"}
      else
        {:ok, 200, [], %{"token" => "myorg"}}
      end
    end)

    assert Hexpm.Billing.Hexpm.change_plan("myorg", %{"plan_id" => "organization-annually"}) ==
             :ok

    assert Hexpm.Billing.Hexpm.update("myorg", %{}) == {:ok, %{}}
    assert Hexpm.Billing.Hexpm.get("myorg") == %{"token" => "myorg"}
    assert Hexpm.Billing.Hexpm.invoice(1) == {:ok, "<html></html>"}
  end

  test "reads the token again for each request", %{path: path} do
    expect(Hexpm.HTTP.Mock, :get, fn _url, headers, _opts ->
      assert_token(headers, "first-token")
      {:ok, 200, [], %{"token" => "myorg"}}
    end)

    assert Hexpm.Billing.Hexpm.get("myorg") == %{"token" => "myorg"}

    # The kubelet replaced the token
    File.write!(path, "second-token")

    expect(Hexpm.HTTP.Mock, :get, fn _url, headers, _opts ->
      assert_token(headers, "second-token")
      {:ok, 200, [], %{"token" => "myorg"}}
    end)

    assert Hexpm.Billing.Hexpm.get("myorg") == %{"token" => "myorg"}
  end

  test "sends no authorization without a token path" do
    Application.delete_env(:hexpm, :billing_token_path)

    expect(Hexpm.HTTP.Mock, :get, fn _url, headers, _opts ->
      refute List.keymember?(headers, "authorization", 0)
      {:ok, 200, [], %{"token" => "myorg"}}
    end)

    assert Hexpm.Billing.Hexpm.get("myorg") == %{"token" => "myorg"}
  end
end

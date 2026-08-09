defmodule Hexpm.Billing.HexpmTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!

  describe "change_plan/2" do
    test "returns :ok when the billing service accepts the change" do
      expect(Hexpm.HTTP.Mock, :post, fn url, _headers, body, _opts ->
        assert url == "http://localhost:4001/api/customers/myorg/plan"
        assert JSON.decode!(body) == %{"plan_id" => "organization-annually"}
        {:ok, 204, [], ""}
      end)

      assert Hexpm.Billing.Hexpm.change_plan("myorg", %{"plan_id" => "organization-annually"}) ==
               :ok
    end

    test "returns the validation errors on 422" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 422, [], %{"errors" => "Cannot change plan while an invoice is past due."}}
      end)

      assert Hexpm.Billing.Hexpm.change_plan("myorg", %{"plan_id" => "organization-annually"}) ==
               {:error, %{"errors" => "Cannot change plan while an invoice is past due."}}
    end

    test "returns an empty error on 500" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 500, [], %{"message" => "Internal server error", "status" => 500}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.change_plan("myorg", %{
                   "plan_id" => "organization-annually"
                 }) == {:error, %{}}
        end)

      assert log =~ "billing change_plan failed for myorg"
    end

    test "returns an empty error when the billing service is unreachable" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.change_plan("myorg", %{
                   "plan_id" => "organization-annually"
                 }) == {:error, %{}}
        end)

      assert log =~ "billing change_plan failed for myorg"
    end
  end
end

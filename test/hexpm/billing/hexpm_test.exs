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

  describe "create/1" do
    test "returns the customer on 200" do
      expect(Hexpm.HTTP.Mock, :post, fn url, _headers, _body, _opts ->
        assert url == "http://localhost:4001/api/customers"
        {:ok, 200, [], %{"token" => "myorg"}}
      end)

      assert Hexpm.Billing.Hexpm.create(%{"token" => "myorg"}) ==
               {:ok, %{"token" => "myorg"}}
    end

    test "returns the validation errors on 422" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 422, [], %{"errors" => %{"email" => ["can't be blank"]}}}
      end)

      assert Hexpm.Billing.Hexpm.create(%{"token" => "myorg"}) ==
               {:error, %{"errors" => %{"email" => ["can't be blank"]}}}
    end

    test "returns an empty error when the request times out" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:error, %Finch.TransportError{reason: :timeout}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.create(%{"token" => "myorg"}) == {:error, %{}}
        end)

      assert log =~ "billing create failed for myorg"
    end
  end

  describe "update/2" do
    test "returns an empty error on 500" do
      expect(Hexpm.HTTP.Mock, :patch, fn _url, _headers, _body, _opts ->
        {:ok, 500, [], %{"message" => "Internal server error"}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.update("myorg", %{"quantity" => 5}) == {:error, %{}}
        end)

      assert log =~ "billing update failed for myorg"
    end
  end

  describe "checkout/2" do
    test "returns an empty error on 500" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 500, [], %{"message" => "Internal server error"}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.checkout("myorg", %{payment_source: "tok_1"}) ==
                   {:error, %{}}
        end)

      assert log =~ "billing checkout failed for myorg"
    end
  end

  describe "void_invoice/2" do
    test "returns an empty error on 500" do
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 500, [], %{"message" => "Internal server error"}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.void_invoice("myorg", "in_1") == {:error, %{}}
        end)

      assert log =~ "billing void_invoice failed for myorg"
    end
  end

  describe "pay_invoice/1" do
    test "returns an empty error on 500" do
      # Hexpm.HTTP.retry/2 is called without retryable statuses, so a 500 is
      # returned to the caller rather than retried
      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
        {:ok, 500, [], %{"message" => "Internal server error"}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.pay_invoice(42) == {:error, %{}}
        end)

      assert log =~ "billing pay_invoice failed for 42"
    end

    test "returns an empty error when the request keeps failing" do
      expect(Hexpm.HTTP.Mock, :post, 3, fn _url, _headers, _body, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      log =
        capture_log(fn ->
          assert Hexpm.Billing.Hexpm.pay_invoice(42) == {:error, %{}}
        end)

      assert log =~ "billing pay_invoice failed for 42"
    end
  end
end

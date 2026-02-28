if Code.ensure_loaded?(Wallaby) do
  defmodule HexpmWeb.Integration.LegacyCheckoutTest do
    use HexpmWeb.FeatureCase, async: false

    @moduletag :integration
    @moduletag timeout: 120_000

    setup do
      app_env(:hexpm, :billing_impl, Hexpm.Billing.Hexpm)
      app_env(:hexpm, :billing_url, "http://localhost:4001")
      app_env(:hexpm, :billing_key, "hex_billing_key")
      app_env(:hexpm, :http_impl, Hexpm.HTTP)

      user = insert(:user)

      %{user: user}
    end

    defp create_legacy_org_with_billing(user) do
      name = unique_org_name()

      {:ok, organization} =
        Hexpm.Accounts.Organizations.create(
          user,
          %{"name" => name},
          audit: Hexpm.TestHelpers.audit_data(user)
        )

      create_billing_customer(name, %{
        "email" => "test@example.com",
        "person" => %{"country" => "US"}
      })

      # Set customer to legacy mode (use_payment_intents: false)
      set_legacy!(name)

      {organization, name}
    end

    describe "legacy checkout flow" do
      test "attaches card via legacy token flow", %{session: session, user: user} do
        {organization, name} = create_legacy_org_with_billing(user)

        session
        |> browser_login(user)
        |> visit_org_billing(organization)

        # Verify the page renders legacy checkout template (StripeCheckout.configure)
        has_legacy_checkout =
          evaluate_js(session, """
            var scripts = document.querySelectorAll('script[src]');
            for (var i = 0; i < scripts.length; i++) {
              if (scripts[i].src.indexOf('checkout.stripe.com') !== -1) return true;
            }
            return false;
          """)

        assert has_legacy_checkout, "Expected legacy checkout.stripe.com script on page"

        # Verify hexpm_billing_post_action is set (legacy checkout uses it)
        post_action =
          evaluate_js(session, """
            return window.hexpm_billing_post_action || null;
          """)

        assert post_action, "Expected hexpm_billing_post_action to be set"
        assert String.contains?(post_action, "billing-token")

        # Create a unique Stripe test token via hexpm_billing's dev endpoint.
        # Each call returns a unique tok_xxx ID, avoiding the unique constraint
        # on payment_sources.payments_token in hexpm_billing's dev database.
        token = create_test_token!()

        # Simulate Stripe Checkout v2 token callback by calling the billing
        # checkout function directly with the test token. This exercises the
        # full chain: hexpm billing_token controller -> hexpm_billing -> Stripe.
        token_json = Jason.encode!(token)

        Wallaby.Browser.execute_script(session, """
          window.hexpm_billing_checkout(#{token_json});
        """)

        # Wait for the POST to complete and page to reload
        Process.sleep(5000)

        # Verify card is shown on billing page
        customer = get_billing_customer(name)
        assert customer["card"]
        assert customer["card"]["brand"] == "Visa"
        assert customer["card"]["last4"] == "4242"

        # Revisit billing page and verify UI shows the card
        visit_org_billing(session, organization)
        assert_has(session, css("button", text: "Update payment method", count: :any))
      end
    end
  end
end

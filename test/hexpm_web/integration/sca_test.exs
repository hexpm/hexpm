if Code.ensure_loaded?(Wallaby) do
  defmodule HexpmWeb.Integration.SCATest do
    use HexpmWeb.FeatureCase, async: false

    @moduletag :integration
    @moduletag timeout: 120_000

    # Stripe test card that requires 3DS authentication
    @card_3ds "4000002760003184"

    @card_expiry "1230"
    @card_cvc "123"

    setup do
      app_env(:hexpm, :billing_impl, Hexpm.Billing.Hexpm)
      app_env(:hexpm, :billing_url, "http://localhost:4001")
      app_env(:hexpm, :billing_key, "hex_billing_key")
      app_env(:hexpm, :http_impl, Hexpm.HTTP)

      user = insert(:user)

      %{user: user}
    end

    defp create_org_with_billing(user) do
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

      {organization, name}
    end

    defp setup_card(session, card_number, expiry \\ @card_expiry, cvc \\ @card_cvc) do
      # The checkout_html is rendered twice: once outside the modal (with CSP nonces,
      # scripts execute, card element mounts here) and once inside the modal (no nonces,
      # scripts blocked). We fill the card element outside the modal and submit
      # that form directly.
      fill_stripe_card(session, card_number, expiry, cvc)

      # Wait for Stripe Elements to fully process the card input
      Process.sleep(2000)

      # Click the first #payment-button on the page (outside the modal, has JS handler)
      Wallaby.Browser.click(session, css("#payment-button", at: 0))

      # Wait for the form handler to execute and Stripe to process
      Process.sleep(3000)

      session
    end

    describe "3DS authentication" do
      test "3DS success sets up payment method", %{session: session, user: user} do
        {organization, _name} = create_org_with_billing(user)

        session
        |> browser_login(user)
        |> visit_org_billing(organization)
        |> setup_card(@card_3ds)

        complete_stripe_3ds(session)

        # Wait for page reload after 3DS completion
        Process.sleep(5000)

        assert_has(session, css("button", text: "Update payment method", count: :any))
      end

      test "3DS failure shows error", %{session: session, user: user} do
        {organization, _name} = create_org_with_billing(user)

        session
        |> browser_login(user)
        |> visit_org_billing(organization)
        |> setup_card(@card_3ds)

        fail_stripe_3ds(session)

        assert_has(session, css("#card-errors"))
      end
    end

    describe "subscription management" do
      test "add seats", %{session: session, user: user} do
        {organization, name} = create_org_with_billing(user)
        add_test_card!(name)
        end_trial!(name)

        # Wait for subscription to be fully active before modifying
        wait_for_billing_status(name, fn customer ->
          sub = customer["subscription"]
          sub && sub["status"] == "active" && sub["current_period_end"]
        end)

        session
        |> browser_login(user)
        |> visit_org_billing(organization, wait_for: "button[data-target='#add-seats']")

        open_modal(session, css("button[data-target='#add-seats']"), "add-seats")
        click(session, css("#add-seats button[type='submit']"))
        assert_flash(session, "info", "seats have been increased")
      end

      test "cancel subscription", %{session: session, user: user} do
        {organization, name} = create_org_with_billing(user)
        add_test_card!(name)
        end_trial!(name)

        # Wait for subscription to be fully active before cancelling
        wait_for_billing_status(name, fn customer ->
          sub = customer["subscription"]
          sub && sub["status"] == "active"
        end)

        session
        |> browser_login(user)
        |> visit_org_billing(organization,
          wait_for: "button[data-target='#cancel-subscription-modal']"
        )

        open_modal(
          session,
          css("button[data-target='#cancel-subscription-modal']"),
          "cancel-subscription-modal"
        )

        click(session, css("#cancel-subscription-modal .btn-danger"))
        assert_flash(session, "info", "cancelled")
      end

      test "change plan monthly to annual", %{session: session, user: user} do
        {organization, name} = create_org_with_billing(user)
        add_test_card!(name)
        end_trial!(name)

        # Wait for subscription to be fully active before changing plan
        wait_for_billing_status(name, fn customer ->
          sub = customer["subscription"]
          sub && sub["status"] == "active"
        end)

        session
        |> browser_login(user)
        |> visit_org_billing(organization, wait_for: "button[data-target='#change-plan']")

        open_modal(session, css("button[data-target='#change-plan']"), "change-plan")
        click(session, css("#change-plan button[type='submit']"))
        assert_flash(session, "info", "switched")
      end
    end
  end
end

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
      wait_until(2000, fn ->
        evaluate_js(session, """
          var errors = document.getElementById('card-errors');
          var hasError = errors && errors.textContent.trim().length > 0;
          var btn = document.getElementById('payment-button');
          return !hasError && btn;
        """)
      end)

      # Click the first #payment-button on the page (outside the modal, has JS handler)
      Wallaby.Browser.click(session, css("#payment-button", at: 0))

      # Wait for Stripe to process (3DS iframe appears or error shows)
      wait_until(3000, fn ->
        evaluate_js(session, """
          var cardEl = document.getElementById('card-element');
          var frames = document.querySelectorAll('iframe');
          for (var i = 0; i < frames.length; i++) {
            if (cardEl && cardEl.contains(frames[i])) continue;
            var name = frames[i].name || '';
            var src = frames[i].src || '';
            if (name.indexOf('challenge') !== -1 || name.indexOf('three-ds') !== -1 ||
                src.indexOf('three-ds') !== -1 || src.indexOf('3ds2') !== -1) {
              return true;
            }
          }
          var errors = document.getElementById('card-errors');
          return errors && errors.textContent.trim().length > 0;
        """)
      end)

      session
    end

    # Submit a form inside a modal via JavaScript fetch() and reload the page.
    # Clicking submit buttons inside Bootstrap modals is unreliable in headless
    # Chrome, so we submit via fetch() with redirect: manual and then reload
    # the page to display the flash message from the redirect.
    defp submit_modal_form(session, form_selector) do
      result =
        evaluate_js(session, """
          var form = document.querySelector('#{form_selector}');
          if (!form) return {error: 'no form found for #{form_selector}'};
          var formData = new URLSearchParams(new FormData(form));
          return await fetch(form.action, {
            method: 'POST',
            body: formData,
            credentials: 'same-origin',
            redirect: 'manual'
          }).then(function(r) {
            return {status: r.status, type: r.type};
          }).catch(function(e) { return {error: e.message}; });
        """)

      assert result["type"] == "opaqueredirect",
             "Expected redirect after form submit, got: #{inspect(result)}"

      Wallaby.Browser.execute_script(session, "window.location.reload();")
      Process.sleep(2000)

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
        wait_until(5000, fn ->
          evaluate_js(session, """
            return !!document.querySelector("button") &&
              document.body.textContent.indexOf('Update payment method') !== -1;
          """)
        end)

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
        submit_modal_form(session, "#add-seats-form")
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

        submit_modal_form(session, "#cancel-subscription-modal form")
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
        submit_modal_form(session, "#change-plan form")
        assert_flash(session, "info", "switched")
      end
    end
  end
end

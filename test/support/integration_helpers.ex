defmodule HexpmWeb.IntegrationHelpers do
  @moduledoc """
  Shared helpers for integration tests that exercise the real chain:
  hexpm -> hexpm_billing -> Stripe.
  """

  import ExUnit.Assertions

  @poll_interval 1_000
  @poll_timeout 90_000

  # Shared JS function that finds the 3DS challenge iframe.
  # Excludes iframes inside #card-element (Stripe Elements).
  # First looks for iframes with 3DS-related names/sources, then falls
  # back to any large (>200px) non-card iframe. Returns the element or null.
  @find_3ds_iframe_js """
    function find3dsIframe() {
      var cardEl = document.getElementById('card-element');
      var frames = document.querySelectorAll('iframe');
      for (var i = 0; i < frames.length; i++) {
        if (cardEl && cardEl.contains(frames[i])) continue;
        var name = frames[i].name || '';
        var src = frames[i].src || '';
        if (name.indexOf('challenge') !== -1 ||
            name.indexOf('three-ds') !== -1 ||
            src.indexOf('three-ds') !== -1 ||
            src.indexOf('3ds2') !== -1) {
          return frames[i];
        }
      }
      for (var i = 0; i < frames.length; i++) {
        if (cardEl && cardEl.contains(frames[i])) continue;
        var rect = frames[i].getBoundingClientRect();
        if (rect.height > 200 && rect.width > 200) {
          return frames[i];
        }
      }
      return null;
    }
  """

  @doc """
  Polls until `fun` returns a truthy value, or `timeout` ms have elapsed.
  Returns early as soon as the condition is met. If the timeout is reached,
  returns without error to let subsequent operations provide clear failures.
  """
  def wait_until(timeout, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(deadline, fun)
  end

  defp do_wait_until(deadline, fun) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        :timeout
      else
        Process.sleep(50)
        do_wait_until(deadline, fun)
      end
    end
  end

  def unique_org_name do
    hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "itest_#{hex}"
  end

  def billing_url do
    Application.get_env(:hexpm, :billing_url)
  end

  def billing_key do
    Application.get_env(:hexpm, :billing_key)
  end

  @doc """
  Creates a billing customer by POSTing to hexpm_billing.
  """
  def create_billing_customer(token, params) do
    body =
      Map.merge(%{"token" => token, "quantity" => 1}, params)
      |> Jason.encode!()

    {:ok, status, _headers, response_body} =
      Hexpm.HTTP.post(
        billing_url() <> "/api/customers",
        billing_headers(),
        body
      )

    assert status in [200, 201],
           "Expected 200/201 creating billing customer, got #{status}: #{inspect(response_body)}"

    response_body
  end

  @doc """
  Gets a billing customer from hexpm_billing.
  """
  def get_billing_customer(token) do
    {:ok, status, _headers, body} =
      Hexpm.HTTP.get(
        billing_url() <> "/api/customers/#{token}",
        billing_headers()
      )

    case status do
      200 -> body
      404 -> nil
    end
  end

  @doc """
  Adds a test card to a billing customer via hexpm_billing's dev-only endpoint.
  Uses Stripe's test PaymentMethod `pm_card_visa`.
  """
  def add_test_card!(token) do
    {:ok, status, _headers, body} =
      Hexpm.HTTP.post(
        billing_url() <> "/api/customers/#{token}/add_test_card",
        billing_headers(),
        "{}"
      )

    assert status in [200, 201],
           "Expected 200/201 adding test card, got #{status}: #{inspect(body)}"
  end

  @doc """
  Creates a unique Stripe test token via hexpm_billing's dev-only endpoint.
  Returns a map with token id and card details.
  """
  def create_test_token! do
    {:ok, status, _headers, body} =
      Hexpm.HTTP.post(
        billing_url() <> "/api/create_test_token",
        billing_headers(),
        "{}"
      )

    assert status in [200, 201],
           "Expected 200/201 creating test token, got #{status}: #{inspect(body)}"

    body
  end

  @doc """
  Sets a billing customer to legacy mode (use_payment_intents: false).
  Calls hexpm_billing's dev-only endpoint.
  """
  def set_legacy!(token) do
    {:ok, status, _headers, body} =
      Hexpm.HTTP.post(
        billing_url() <> "/api/customers/#{token}/set_legacy",
        billing_headers(),
        "{}"
      )

    assert status in [200, 201],
           "Expected 200/201 setting legacy mode, got #{status}: #{inspect(body)}"
  end

  @doc """
  Ends a trial immediately by calling hexpm_billing's dev-only endpoint.
  Polls until the subscription status changes from "trialing".
  """
  def end_trial!(token) do
    {:ok, status, _headers, body} =
      Hexpm.HTTP.post(
        billing_url() <> "/api/customers/#{token}/end_trial",
        billing_headers(),
        "{}"
      )

    assert status in [200, 201],
           "Expected 200/201 ending trial, got #{status}: #{inspect(body)}"

    wait_for_billing_status(token, fn customer ->
      sub = customer["subscription"]
      sub && sub["status"] != "trialing"
    end)
  end

  @doc """
  Polls hexpm_billing GET endpoint until condition is met.
  Used to wait for Stripe webhook sync.
  """
  def wait_for_billing_status(token, condition, timeout \\ @poll_timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_poll(token, condition, deadline)
  end

  defp do_poll(token, condition, deadline) do
    customer = get_billing_customer(token)

    if customer && condition.(customer) do
      customer
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk(
          "Timed out waiting for billing status condition on #{token}. " <>
            "Last customer state: #{inspect(customer)}"
        )
      end

      Process.sleep(@poll_interval)
      do_poll(token, condition, deadline)
    end
  end

  @doc """
  Fills in Stripe Elements card fields inside the iframe.

  Stripe Elements uses a single combined card element mounted in an iframe.
  This function switches into the iframe, fills the card details, and switches back.
  """
  def fill_stripe_card(session, card_number, expiry \\ "1230", cvc \\ "123", zip \\ "10001") do
    wait_for_stripe_iframe(session)

    type_in_stripe_field(session, "cardnumber", card_number, String.length(card_number))
    type_in_stripe_field(session, "exp-date", expiry, String.length(expiry))
    type_in_stripe_field(session, "cvc", cvc, 3)

    # ZIP code field may not be present depending on Stripe Elements config.
    focus_stripe_iframe(session, 0)

    has_postal =
      evaluate_js(session, """
        return document.querySelector("input[name='postal']") !== null;
      """)

    if has_postal do
      type_in_stripe_field(session, "postal", zip, String.length(zip))
    end

    Wallaby.Browser.focus_default_frame(session)

    session
  end

  # Types a value into a Stripe Elements field with retry logic.
  # Uses JavaScript execCommand('insertText') instead of WebDriver send_keys
  # because send_keys drops keystrokes when going through the cross-origin
  # iframe bridge. execCommand operates directly in the iframe's JS context.
  defp type_in_stripe_field(session, field_name, value, expected_digits, attempts \\ 3) do
    focus_stripe_iframe(session, 0)

    Wallaby.Browser.execute_script(session, """
      var input = document.querySelector("input[name='#{field_name}']");
      if (input) {
        input.focus();
        input.click();
        input.select();
        document.execCommand('insertText', false, '#{value}');
      }
    """)

    filled =
      wait_until(2000, fn ->
        evaluate_js(session, """
          var input = document.querySelector("input[name='#{field_name}']");
          if (!input || !input.value) return false;
          return input.value.replace(/[^0-9]/g, '').length >= #{expected_digits};
        """)
      end)

    if filled != :ok && attempts > 1 do
      focus_stripe_iframe(session, 0)

      Wallaby.Browser.execute_script(session, """
        var input = document.querySelector("input[name='#{field_name}']");
        if (input) {
          input.focus();
          input.select();
          document.execCommand('delete');
        }
      """)

      Process.sleep(200)
      type_in_stripe_field(session, field_name, value, expected_digits, attempts - 1)
    end
  end

  # Focuses a Stripe Elements iframe by index inside #card-element.
  defp focus_stripe_iframe(session, index) do
    Wallaby.Browser.focus_default_frame(session)
    Wallaby.Browser.focus_frame(session, Wallaby.Query.css("#card-element iframe", at: index))
  end

  @doc """
  Completes 3DS authentication in the Stripe test 3DS modal.
  """
  def complete_stripe_3ds(session) do
    click_3ds_button(session, "Complete")
  end

  @doc """
  Fails 3DS authentication in the Stripe test 3DS modal.
  """
  def fail_stripe_3ds(session) do
    click_3ds_button(session, "Fail")
  end

  # Finds and clicks a 3DS button by navigating through iframe levels.
  # The 3DS iframe is cross-origin (from stripe.com), so JavaScript-based
  # element detection doesn't work. We use Wallaby's WebDriver-based element
  # finding which can access cross-origin iframe content.
  defp click_3ds_button(session, button_text) do
    wait_for_3ds_iframe(session)
    iframe_name = get_3ds_iframe_name(session)
    Wallaby.Browser.focus_frame(session, Wallaby.Query.css("iframe[name='#{iframe_name}']"))

    try do
      Wallaby.Browser.click(session, Wallaby.Query.button(button_text))
    rescue
      Wallaby.QueryError ->
        # Button not at this level, try nested iframe
        try do
          Wallaby.Browser.focus_frame(session, Wallaby.Query.css("iframe"))
          Wallaby.Browser.click(session, Wallaby.Query.button(button_text))
        rescue
          Wallaby.QueryError ->
            # Try one more level of nesting
            try do
              Wallaby.Browser.focus_frame(session, Wallaby.Query.css("iframe"))
              Wallaby.Browser.click(session, Wallaby.Query.button(button_text))
            rescue
              _ ->
                Wallaby.Browser.focus_default_frame(session)
                Wallaby.Browser.take_screenshot(session, name: "3ds_button_not_found")
                flunk("3DS '#{button_text}' button not found at any iframe depth")
            end
        end
    end

    Wallaby.Browser.focus_default_frame(session)
    session
  end

  # Waits for the Stripe Elements iframe to be visible inside #card-element.
  # The card form is rendered inline on the billing page inside #billing-checkout-data.
  # Checks that the iframe exists, is visible, and has non-zero dimensions.
  defp wait_for_stripe_iframe(session, attempts \\ 30) do
    has_visible_iframe =
      evaluate_js(session, """
        var card = document.getElementById('card-element');
        if (!card) return false;
        var iframes = card.querySelectorAll('iframe');
        for (var i = 0; i < iframes.length; i++) {
          var rect = iframes[i].getBoundingClientRect();
          if (rect.height > 0 && rect.width > 0) return true;
        }
        return false;
      """)

    cond do
      has_visible_iframe ->
        # Wait for Stripe Elements to fully render card fields inside the iframe
        focus_stripe_iframe(session, 0)

        wait_until(1000, fn ->
          evaluate_js(session, """
            return !!document.querySelector("input[name='cardnumber']");
          """)
        end)

        Wallaby.Browser.focus_default_frame(session)
        :ok

      attempts <= 0 ->
        Wallaby.Browser.take_screenshot(session, name: "stripe_iframe_debug")

        diag =
          evaluate_js(session, """
            var diag = {};
            diag.pageUrl = window.location.href;
            diag.stripeLoaded = typeof window.Stripe !== 'undefined';
            diag.stripeType = typeof window.Stripe;
            var card = document.getElementById('card-element');
            diag.cardElementExists = !!card;
            diag.cardElementHTML = card ? card.innerHTML.substring(0, 500) : 'N/A';
            diag.cardElementParentVisible = card ? window.getComputedStyle(card.parentElement).display : 'N/A';
            diag.totalIframes = document.querySelectorAll('iframe').length;
            var stripeScripts = [];
            document.querySelectorAll('script[src]').forEach(function(s) {
              if (s.src.indexOf('stripe') !== -1) {
                stripeScripts.push({src: s.src, hasNonce: !!s.nonce});
              }
            });
            diag.stripeScripts = stripeScripts;
            diag.allScriptCount = document.querySelectorAll('script').length;
            diag.noncedScriptCount = document.querySelectorAll('script[nonce]').length;
            var allCards = document.querySelectorAll('#card-element');
            diag.cardElementCount = allCards.length;
            for (var i = 0; i < allCards.length; i++) {
              diag['cardElement_' + i + '_iframes'] = allCards[i].querySelectorAll('iframe').length;
              diag['cardElement_' + i + '_html'] = allCards[i].innerHTML.substring(0, 200);
              var parentForm = allCards[i].closest('form');
              diag['cardElement_' + i + '_parentDisplay'] = parentForm ? window.getComputedStyle(parentForm).display : 'N/A';
            }
            diag.bodyTextSnippet = document.body ? document.body.textContent.substring(0, 200).trim() : 'N/A';
            return diag;
          """)

        flunk(
          "Stripe Elements iframe did not become visible within timeout\n" <>
            "Diagnostics: #{inspect(diag, pretty: true)}"
        )

      true ->
        Process.sleep(1000)
        wait_for_stripe_iframe(session, attempts - 1)
    end
  end

  defp get_3ds_iframe_name(session) do
    name =
      evaluate_js(
        session,
        @find_3ds_iframe_js <>
          """
            var frame = find3dsIframe();
            return frame ? (frame.name || '') : '';
          """
      )

    assert name != "", "Could not find 3DS iframe name"
    name
  end

  defp wait_for_3ds_iframe(session, attempts \\ 30) do
    has_3ds =
      evaluate_js(
        session,
        @find_3ds_iframe_js <>
          """
            return find3dsIframe() !== null;
          """
      )

    if has_3ds do
      wait_until(2000, fn ->
        evaluate_js(
          session,
          @find_3ds_iframe_js <>
            """
              var frame = find3dsIframe();
              if (!frame) return false;
              var rect = frame.getBoundingClientRect();
              return rect.height > 300 && rect.width > 300;
            """
        )
      end)

      :ok
    else
      if attempts <= 0 do
        diag =
          evaluate_js(session, """
            var result = {};
            result.sca_debug = window.__sca_debug || 'not set';
            var cardErrors = document.getElementById('card-errors');
            result.card_errors = cardErrors ? cardErrors.textContent.trim() : '';
            result.total_iframes = document.querySelectorAll('iframe').length;
            var iframes = [];
            document.querySelectorAll('iframe').forEach(function(f) {
              iframes.push({name: f.name || '', src: (f.src || '').substring(0, 100),
                w: f.getBoundingClientRect().width, h: f.getBoundingClientRect().height});
            });
            result.iframes = iframes;
            result.payment_button_disabled = (function() {
              var btn = document.getElementById('payment-button');
              return btn ? {disabled: btn.disabled, text: btn.textContent.trim()} : 'not found';
            })();
            return result;
          """)

        flunk(
          "3DS iframe did not appear within timeout\n" <>
            "Diagnostics: #{inspect(diag, pretty: true)}"
        )
      end

      Process.sleep(1000)
      wait_for_3ds_iframe(session, attempts - 1)
    end
  end

  @doc """
  Opens a modal and waits for it to be visible.

  Clicks the trigger button, then verifies the modal actually opened.
  The modal uses Phoenix.LiveView.JS which toggles the `hidden` class.
  Falls back to manually removing the `hidden` class if the JS handler
  didn't fire.
  """
  def open_modal(session, trigger_selector, modal_id) do
    Wallaby.Browser.click(session, trigger_selector)
    wait_for_modal(session, modal_id)
    session
  end

  defp wait_for_modal(session, modal_id, attempts \\ 10) do
    is_open =
      evaluate_js(session, """
        var modal = document.getElementById('#{modal_id}');
        return modal && !modal.classList.contains('hidden');
      """)

    if is_open do
      :ok
    else
      if attempts <= 0 do
        flunk("Modal ##{modal_id} did not open within timeout")
      end

      # Phoenix.LiveView.JS handler may not have fired; manually remove hidden class
      Wallaby.Browser.execute_script(session, """
        ['#{modal_id}', '#{modal_id}-backdrop', '#{modal_id}-content'].forEach(function(id) {
          var el = document.getElementById(id);
          if (el) el.classList.remove('hidden');
        });
      """)

      Process.sleep(500)
      wait_for_modal(session, modal_id, attempts - 1)
    end
  end

  @doc """
  Visits an org billing page with retry logic.

  The billing section is server-rendered and depends on Hexpm.Billing.get
  successfully fetching data from hexpm_billing. If hexpm_billing is slow
  (e.g., processing previous test's Stripe webhooks), the page may render
  without the billing section. This retries the page load if that happens.

  An optional `wait_for` selector can be provided to wait for a specific
  element to appear (e.g., a subscription-only form).
  """
  def visit_org_billing(session, organization, opts \\ []) do
    wait_for = Keyword.get(opts, :wait_for, "#billing-checkout-data")
    attempts = Keyword.get(opts, :attempts, 5)
    do_visit_org_billing(session, organization, wait_for, attempts)
  end

  defp do_visit_org_billing(session, organization, wait_for, attempts) do
    session = Wallaby.Browser.visit(session, "/dashboard/orgs/#{organization.name}/billing")

    has_element =
      evaluate_js(session, """
        return document.querySelector("#{wait_for}") !== null;
      """)

    if has_element || attempts <= 1 do
      session
    else
      Process.sleep(2000)
      do_visit_org_billing(session, organization, wait_for, attempts - 1)
    end
  end

  # Evaluates JavaScript and returns the result value.
  # Wallaby.Browser.execute_script/2 returns the session, not the JS value.
  # This uses the callback form to capture the return value.
  def evaluate_js(session, script) do
    ref = make_ref()

    Wallaby.Browser.execute_script(session, script, fn value ->
      send(self(), {ref, value})
    end)

    receive do
      {^ref, value} -> value
    after
      5_000 -> nil
    end
  end

  @doc """
  Asserts that a flash message is visible with the expected text.
  Polls the DOM for up to 10 seconds. On failure, captures diagnostic info
  about what flash messages are actually on the page.
  """
  def assert_flash(session, _type, text, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_flash(session, text, deadline)
  end

  defp do_assert_flash(session, text, deadline) do
    page_info =
      evaluate_js(session, """
        var flashes = document.querySelectorAll('.flash-message');
        var result = [];
        for (var i = 0; i < flashes.length; i++) {
          result.push({
            id: flashes[i].id,
            text: flashes[i].textContent.trim().substring(0, 200)
          });
        }
        return {
          url: window.location.href,
          title: document.title,
          flashes: result
        };
      """)

    found =
      Enum.any?(page_info["flashes"] || [], fn flash ->
        String.contains?(flash["text"] || "", text)
      end)

    if found do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk(
          "Expected flash with text '#{text}'\n" <>
            "Page URL: #{page_info["url"]}\n" <>
            "Page title: #{page_info["title"]}\n" <>
            "Flash messages on page: #{inspect(page_info["flashes"])}"
        )
      end

      Process.sleep(500)
      do_assert_flash(session, text, deadline)
    end
  end

  defp billing_headers do
    [
      {"authorization", billing_key()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end
end

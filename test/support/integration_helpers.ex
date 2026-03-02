defmodule HexpmWeb.IntegrationHelpers do
  @moduledoc """
  Shared helpers for integration tests that exercise the real chain:
  hexpm -> hexpm_billing -> Stripe.
  """

  import ExUnit.Assertions

  @poll_interval 1_000
  @poll_timeout 60_000

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
        :ok
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
  Patches fetch() in the browser to rewrite the billing API URL.

  hexpm_billing generates checkout HTML with apiBaseUrl pointing to its configured
  hexpm URL (e.g. localhost:4000), but the test server runs on a different port.
  This intercepts fetch calls and rewrites the URL to point to the test server.
  """
  def patch_billing_api_url(session) do
    test_url = Application.get_env(:wallaby, :base_url)

    Wallaby.Browser.execute_script(session, """
      if (!window.__fetch_patched) {
        var originalFetch = window.fetch;
        window.fetch = function(url, options) {
          if (typeof url === 'string' && url.indexOf('/dashboard/billing-api') !== -1) {
            url = url.replace(/https?:\\/\\/[^/]+/, '#{test_url}');
          }
          return originalFetch.call(this, url, options);
        };
        window.__fetch_patched = true;
      }
    """)

    session
  end

  @doc """
  Fills in Stripe Elements card fields inside the iframe.

  Stripe Elements uses a single combined card element mounted in an iframe.
  This function switches into the iframe, fills the card details, and switches back.
  """
  def fill_stripe_card(session, card_number, expiry \\ "1230", cvc \\ "123", zip \\ "10001") do
    wait_for_stripe_iframe(session)

    # Stripe Elements uses a cross-origin iframe from js.stripe.com.
    # ChromeDriver's findElement intermittently fails in cross-origin iframes,
    # even though executeScript works fine. We use JS to focus/click fields
    # and WebDriver's send_keys to type values.
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
      js_focus_and_click(session, "postal")
      Wallaby.Browser.send_keys(session, String.graphemes(zip))
    end

    Wallaby.Browser.focus_default_frame(session)

    session
  end

  # Types a value into a Stripe Elements field with retry logic.
  # Stripe Elements in headless Chrome can sometimes miss keystrokes,
  # especially when the field auto-advances or loses focus. This retries
  # the entire field input if not enough digits were entered.
  defp type_in_stripe_field(session, field_name, value, expected_digits, attempts \\ 3) do
    focus_stripe_iframe(session, 0)
    js_focus_and_click(session, field_name)
    Wallaby.Browser.send_keys(session, String.graphemes(value))

    filled =
      wait_until(2000, fn ->
        evaluate_js(session, """
          var input = document.querySelector("input[name='#{field_name}']");
          if (!input || !input.value) return false;
          return input.value.replace(/[^0-9]/g, '').length >= #{expected_digits};
        """)
      end)

    if filled != :ok && attempts > 1 do
      # Clear the field and retry
      focus_stripe_iframe(session, 0)
      js_focus_and_click(session, field_name)

      Wallaby.Browser.execute_script(session, """
        var input = document.querySelector("input[name='#{field_name}']");
        if (input) { input.select(); }
      """)

      Wallaby.Browser.send_keys(session, [:backspace])
      Process.sleep(200)
      type_in_stripe_field(session, field_name, value, expected_digits, attempts - 1)
    end
  end

  # Uses JavaScript to focus and click an input field inside a Stripe iframe.
  # This is more reliable than WebDriver's findElement for cross-origin iframes.
  defp js_focus_and_click(session, field_name) do
    Wallaby.Browser.execute_script(session, """
      var input = document.querySelector("input[name='#{field_name}']");
      if (input) {
        input.focus();
        input.click();
      }
    """)

    wait_until(100, fn ->
      evaluate_js(session, """
        var input = document.querySelector("input[name='#{field_name}']");
        return input && document.activeElement === input;
      """)
    end)
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
  # Checks that the iframe exists, is visible, and has non-zero dimensions
  # (which ensures the Bootstrap modal animation has completed).
  #
  # If the modal isn't open (Bootstrap JS hadn't initialized when the button
  # was clicked), forces it open via jQuery.
  defp wait_for_stripe_iframe(session, attempts \\ 30) do
    state =
      evaluate_js(session, """
        var modal = document.getElementById('payment-method-modal');
        var modalOpen = modal && window.getComputedStyle(modal).display !== 'none';
        var card = document.getElementById('card-element');
        var hasVisibleIframe = false;
        if (card) {
          var iframes = card.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            var rect = iframes[i].getBoundingClientRect();
            if (rect.height > 0 && rect.width > 0) { hasVisibleIframe = true; break; }
          }
        }
        return {modalOpen: modalOpen, hasVisibleIframe: hasVisibleIframe};
      """)

    modal_open = state["modalOpen"]
    has_visible_iframe = state["hasVisibleIframe"]

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

      not modal_open ->
        # Bootstrap JS hadn't initialized when the button was clicked.
        # Force the modal open via jQuery and retry.
        Wallaby.Browser.execute_script(session, """
          if (typeof $ !== 'undefined') {
            $('#payment-method-modal').modal('show');
          }
        """)

        Process.sleep(1000)
        wait_for_stripe_iframe(session, attempts - 1)

      attempts <= 0 ->
        Wallaby.Browser.take_screenshot(session, name: "stripe_iframe_debug")

        diag =
          evaluate_js(session, """
            var diag = {};
            diag.pageUrl = window.location.href;
            diag.stripeLoaded = typeof window.Stripe !== 'undefined';
            diag.stripeType = typeof window.Stripe;
            diag.jqueryLoaded = typeof window.$ !== 'undefined';
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
              diag['cardElement_' + i + '_inModal'] = !!allCards[i].closest('.modal');
              diag['cardElement_' + i + '_parentDisplay'] = parentForm ? window.getComputedStyle(parentForm).display : 'N/A';
            }
            diag.bodyTextSnippet = document.body ? document.body.textContent.substring(0, 200).trim() : 'N/A';
            return diag;
          """)

        flunk(
          "Stripe Elements iframe did not become visible within timeout (modal is open)\n" <>
            "Diagnostics: #{inspect(diag, pretty: true)}"
        )

      true ->
        Process.sleep(1000)
        wait_for_stripe_iframe(session, attempts - 1)
    end
  end

  # Gets the name attribute of the 3DS challenge iframe.
  # Excludes iframes inside #card-element (Stripe Elements) to avoid
  # matching the card input iframe instead of the 3DS modal.
  defp get_3ds_iframe_name(session) do
    name =
      evaluate_js(session, """
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
            return name;
          }
        }
        for (var i = 0; i < frames.length; i++) {
          if (cardEl && cardEl.contains(frames[i])) continue;
          var rect = frames[i].getBoundingClientRect();
          if (rect.height > 200 && rect.width > 200) {
            return frames[i].name || '';
          }
        }
        return '';
      """)

    assert name != "", "Could not find 3DS iframe name"
    name
  end

  # Waits for the 3DS challenge iframe to appear.
  # Excludes iframes inside #card-element (Stripe Elements).
  defp wait_for_3ds_iframe(session, attempts \\ 30) do
    has_3ds =
      evaluate_js(session, """
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
            return true;
          }
          var rect = frames[i].getBoundingClientRect();
          if (rect.height > 200 && rect.width > 200) {
            return true;
          }
        }
        return false;
      """)

    if has_3ds do
      wait_until(2000, fn ->
        evaluate_js(session, """
          var cardEl = document.getElementById('card-element');
          var frames = document.querySelectorAll('iframe');
          for (var i = 0; i < frames.length; i++) {
            if (cardEl && cardEl.contains(frames[i])) continue;
            var rect = frames[i].getBoundingClientRect();
            if (rect.height > 300 && rect.width > 300) return true;
          }
          return false;
        """)
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
  Opens a Bootstrap modal and waits for it to be visible.

  Clicks the trigger button, then verifies the modal actually opened.
  If Bootstrap JS hasn't initialized its event listeners yet, falls back
  to opening the modal via jQuery.
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
        return modal && window.getComputedStyle(modal).display !== 'none';
      """)

    if is_open do
      wait_until(300, fn ->
        evaluate_js(session, """
          var modal = document.getElementById('#{modal_id}');
          return modal && modal.classList.contains('show');
        """)
      end)

      :ok
    else
      if attempts <= 0 do
        flunk("Modal ##{modal_id} did not open within timeout")
      end

      Wallaby.Browser.execute_script(session, """
        if (typeof $ !== 'undefined') {
          $('##{modal_id}').modal('show');
        }
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
  element to appear (e.g., a subscription-only button).
  """
  def visit_org_billing(session, organization, opts \\ []) do
    wait_for = Keyword.get(opts, :wait_for, "button[data-target='#payment-method-modal']")
    attempts = Keyword.get(opts, :attempts, 5)
    do_visit_org_billing(session, organization, wait_for, attempts)
  end

  defp do_visit_org_billing(session, organization, wait_for, attempts) do
    session =
      session
      |> Wallaby.Browser.visit("/dashboard/orgs/#{organization.name}")
      |> patch_billing_api_url()

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
  about what alerts are actually on the page.
  """
  def assert_flash(session, type, text, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_flash(session, type, text, deadline)
  end

  defp do_assert_flash(session, type, text, deadline) do
    page_info =
      evaluate_js(session, """
        var alerts = document.querySelectorAll('.alert');
        var result = [];
        for (var i = 0; i < alerts.length; i++) {
          result.push({
            classes: alerts[i].className,
            text: alerts[i].textContent.trim().substring(0, 200)
          });
        }
        return {
          url: window.location.href,
          title: document.title,
          alerts: result
        };
      """)

    found =
      Enum.any?(page_info["alerts"] || [], fn alert ->
        String.contains?(alert["classes"] || "", "alert-#{type}") &&
          String.contains?(alert["text"] || "", text)
      end)

    if found do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk(
          "Expected .alert-#{type} with text '#{text}'\n" <>
            "Page URL: #{page_info["url"]}\n" <>
            "Page title: #{page_info["title"]}\n" <>
            "Alerts on page: #{inspect(page_info["alerts"])}"
        )
      end

      Process.sleep(500)
      do_assert_flash(session, type, text, deadline)
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

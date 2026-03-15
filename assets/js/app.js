import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import PasswordStrength from "./hooks/password_strength";
import PasswordMatch from "./hooks/password_match";
import { CopyButton } from "./hooks/copy_button";
import { PrintButton } from "./hooks/print_button";
import { DownloadButton } from "./hooks/download_button";
import { PermissionGroup } from "./hooks/permission_group";

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let Hooks = {
  PasswordStrength,
  PasswordMatch,
  CopyButton,
  PrintButton,
  DownloadButton,
  PermissionGroup,
};
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

liveSocket.connect();

import $ from "jquery";
import hljs from "highlight.js/lib/core";
import elixir from "highlight.js/lib/languages/elixir";

// Highlight syntax on blog, policy, and docs pages
hljs.registerLanguage("elixir", elixir);
hljs.highlightAll();

// Focus username, 2FA or search field
if (document.getElementById("username")) {
  document.getElementById("username").focus();
} else if (document.getElementById("code")) {
  document.getElementById("code").focus();
}

// Auto-format device verification code input
const userCodeInput = document.getElementById("user_code");
if (userCodeInput) {
  userCodeInput.addEventListener("input", function (e) {
    let value = e.target.value.replace(/[^A-Z0-9]/g, "").toUpperCase();
    if (value.length > 4) {
      value = value.slice(0, 4) + "-" + value.slice(4, 8);
    }
    e.target.value = value;
  });
}

// Billing checkout called by hexpm_billing templates
function billingCheckout(token) {
  const el = document.getElementById("billing-checkout-data");
  const postAction = el && el.dataset.postAction;
  const billingCsrfToken = el && el.dataset.csrfToken;
  $.post(postAction, {
    token: token,
    _csrf_token: billingCsrfToken,
  })
    .done(function () {
      window.location.reload();
    })
    .fail(function (data) {
      var response = JSON.parse(data.responseText);
      $("div.flash").html(
        '<div class="alert alert-danger" role="alert">' +
          "<strong>Failed to update payment method</strong><br>" +
          response.errors +
          "</div>",
      );
    });
}

window.hexpm_billing_checkout = billingCheckout;
window.$ = $;
window.liveSocket = liveSocket;

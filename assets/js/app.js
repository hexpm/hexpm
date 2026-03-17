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

  fetch(postAction, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: token, _csrf_token: billingCsrfToken }),
  })
    .then(function (response) {
      if (response.ok) {
        window.location.reload();
      } else {
        return response.json().then(function (data) {
          const flash = document.getElementById("flash-container");
          if (flash) {
            flash.innerHTML =
              '<div class="flash-message flex items-center gap-3 px-4 py-3 rounded-lg border shadow-lg bg-red-100 border-red-300" role="alert">' +
              '<div class="flex-1 text-small leading-5 text-red-800">' +
              "<strong>Failed to update payment method</strong><br>" +
              data.errors +
              "</div></div>";
          }
        });
      }
    });
}

window.hexpm_billing_checkout = billingCheckout;
window.liveSocket = liveSocket;

// README iframe: show spinner until loaded, fall back to description if no readme
var readmeFrame = document.getElementById("readme-frame");

window.addEventListener("message", function (event) {
  if (!event.data || !readmeFrame) return;

  if (event.data.type === "readme-height" &&
      typeof event.data.height === "number" &&
      event.data.height > 0 && event.data.height < 100000) {
    readmeFrame.classList.remove("opacity-0", "h-0", "overflow-hidden");
    readmeFrame.style.height = Math.ceil(event.data.height) + "px";
    var loading = document.getElementById("readme-loading");
    if (loading) loading.remove();
  }

  if (event.data.type === "readme-not-found") {
    var loading = document.getElementById("readme-loading");
    if (loading) loading.remove();
    readmeFrame.remove();
    var fallback = document.getElementById("readme-fallback");
    if (fallback) fallback.classList.remove("hidden");
  }
});

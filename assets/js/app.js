import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import PasswordStrength from "./hooks/password_strength";
import PasswordMatch from "./hooks/password_match";
import { CopyButton } from "./hooks/copy_button";
import { PrintButton } from "./hooks/print_button";
import { DownloadButton } from "./hooks/download_button";
import { PermissionGroup } from "./hooks/permission_group";
import { KeyExpiry } from "./hooks/key_expiry";
import { TFACodeInput } from "./hooks/tfa_code_input";
import { SubmitOnce } from "./hooks/submit_once";
import { AutoSubmit } from "./hooks/auto_submit";
import { NavigateOnChange } from "./hooks/navigate_on_change";
import { ConfirmSubmit } from "./hooks/confirm_submit";
import { initializeTheme, syncReadmeFrameTheme, resolveTheme } from "./theme";
import { SearchShortcut } from "./hooks/search_shortcut";
import { SearchInputSync } from "./hooks/search_input_sync";
import { ToggleGroup } from "./hooks/toggle_group";
import { RuleToggle } from "./hooks/rule_toggle";
import { ScrollActiveIntoView } from "./hooks/scroll_active_into_view";
import { OverrideList } from "./hooks/override_list";
import { PrivateRepoTabs } from "./hooks/private_repo_tabs";
import { PolicyDirtyState } from "./hooks/policy_dirty_state";
import LineHighlight from "./hooks/line_highlight";
import { InfiniteScroll } from "./hooks/diff";
import { FormSync } from "./hooks/form_sync";
import { FileFinder } from "./hooks/file_finder";

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
  KeyExpiry,
  TFACodeInput,
  SubmitOnce,
  AutoSubmit,
  NavigateOnChange,
  ConfirmSubmit,
  SearchShortcut,
  SearchInputSync,
  ToggleGroup,
  RuleToggle,
  ScrollActiveIntoView,
  OverrideList,
  PrivateRepoTabs,
  PolicyDirtyState,
  LineHighlight,
  InfiniteScroll,
  FormSync,
  FileFinder,
};
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

liveSocket.connect();
initializeTheme();

// Focus username, 2FA or search field
if (document.getElementById("username")) {
  document.getElementById("username").focus();
} else if (document.getElementById("code")) {
  document.getElementById("code").focus();
}

// Position CSS tooltips with viewport-relative coordinates so they can escape
// ancestor overflow containers (the .tooltip pseudo-elements use position: fixed).
function positionTooltip(el) {
  const rect = el.getBoundingClientRect();
  el.style.setProperty("--tooltip-x", `${rect.left + rect.width / 2}px`);
  el.style.setProperty("--tooltip-y", `${rect.top}px`);
}

document.addEventListener("mouseover", function (e) {
  if (!(e.target instanceof Element)) return;
  const tooltip = e.target.closest(".tooltip");
  if (!tooltip) return;
  const from = e.relatedTarget instanceof Element ? e.relatedTarget.closest(".tooltip") : null;
  if (from === tooltip) return;
  positionTooltip(tooltip);
});

document.addEventListener("focusin", function (e) {
  if (!(e.target instanceof Element)) return;
  const tooltip = e.target.closest(".tooltip");
  if (tooltip) positionTooltip(tooltip);
});

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
              (typeof data.errors === "string" ? data.errors : JSON.stringify(data.errors)) +
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
var pendingInitialHash = window.location.hash ? window.location.hash.slice(1) : null;

window.addEventListener("message", function (event) {
  if (!event.data || !readmeFrame) return;

  if (
    event.data.type === "readme-height" &&
    typeof event.data.height === "number" &&
    event.data.height > 0 &&
    event.data.height < 100000
  ) {
    readmeFrame.classList.remove("opacity-0", "h-0", "overflow-hidden");
    readmeFrame.style.height = Math.ceil(event.data.height) + "px";
    syncReadmeFrameTheme(resolveTheme());
    var loading = document.getElementById("readme-loading");
    if (loading) loading.remove();

    if (pendingInitialHash !== null && readmeFrame.contentWindow) {
      readmeFrame.contentWindow.postMessage(
        { type: "scroll-to-anchor", id: pendingInitialHash },
        "*",
      );
      pendingInitialHash = null;
    }
  }

  if (event.data.type === "readme-not-found") {
    var loading = document.getElementById("readme-loading");
    if (loading) loading.remove();
    readmeFrame.remove();
    var fallback = document.getElementById("readme-fallback");
    if (fallback) fallback.classList.remove("hidden");
  }

  if (
    event.data.type === "readme-anchor" &&
    typeof event.data.id === "string" &&
    typeof event.data.top === "number"
  ) {
    var frameTop = readmeFrame.getBoundingClientRect().top + window.scrollY;
    window.scrollTo({ top: frameTop + event.data.top, behavior: "smooth" });
    if (event.data.id) {
      history.replaceState(null, "", "#" + event.data.id);
    } else {
      history.replaceState(null, "", window.location.pathname + window.location.search);
    }
  }
});

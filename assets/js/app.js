// TODO: Remove dependencies to reduce, start with jquery

import "phoenix_html"
import { Socket } from "phoenix"
import LiveSocket from "phoenix_live_view"
import $ from "jquery"
import hljs from 'highlight.js/lib/highlight'
import elixir from 'highlight.js/lib/languages/elixir'

import "../css/app.css"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } })
liveSocket.connect()


class App {
  constructor() {
    // Focus username or search field
    if ($("#username").length > 0) {
      $("#username").focus()
    } else {
      $("[name='search']").focus()
    }

    // Expand user menu
    $("#user-menu-button").on("click", () =>
      $("#user-menu").toggleClass("hidden")
    )

    // Expand mobile menu
    $("#main-menu-button").on("click", () =>
      $("#main-menu").toggleClass("hidden")
    )
  }
}

window.app = new App()
window.hexpm_billing_checkout = app.billing_checkout
window.$ = $
window.liveSocket = liveSocket

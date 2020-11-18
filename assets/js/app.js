// TODO: Remove dependencies to reduce, start with jquery

import "phoenix_html"
import { Socket } from "phoenix"
import LiveSocket from "phoenix_live_view"
import $ from "jquery"
import 'alpinejs'
import hljs from 'highlight.js/lib/highlight'
import elixir from 'highlight.js/lib/languages/elixir'

import "../css/app.css"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } })
liveSocket.connect()

// TODO: Replace jquery with alpine.js

class App {
  constructor() {
    this.focus()
    this.expandUserMenu()
    this.expandMobileMenu()
  }

  focus() {
    // Focus username or search field
    if ($("#username").length > 0) {
      $("#username").trigger("focus")
    } else {
      $("[name='search']").trigger("focus")
    }
  }

  expandUserMenu() {
    $("#user-menu-button").on("click", () =>
      $("#user-menu").toggleClass("hidden")
    )
  }

  expandMobileMenu() {
    $("#main-menu-button").on("click", () =>
      $("#main-menu").toggleClass("hidden")
    )
  }
}


window.Components = {
  listBox(options) {
    return {
      activeDescendant: null,
      optionCount: null,
      open: false,
      selected: null,
      value: 1,

      init() {
        this.optionCount = this.$refs.listbox.children.length

        this.$watch("selected", value => {
          if (!this.open) return

          if (this.selected === null) {
            this.activeDescendant = ""
            return
          }

          this.activeDescendant = this.$refs.listbox.children[this.selected - 1].id
        })
      },

      choose(option) {
        this.value = option
        this.open = false
      },

      onButtonClick() {
        if (this.open) return
        this.selected = this.value
        this.open = true

        this.$nextTick(() => {
          this.$refs.listbox.focus()
          this.$refs.listbox.children[this.selected - 1].scrollIntoView({block: "nearest"})
        })
      },

      onOptionSelect() {
        if (this.selected !== null)
          this.vaule = this.selected

        this.$refs.listbox.children[this.selected - 1].getElementsByTagName("a")[0].click()
        this.$refs.button.focus()
        this.open = false
      },

      onEscape() {
        this.open = false
      },

      onArrowUp() {
        this.selected = this.selected - 1 < 1 ? this.optionCount : this.selected - 1
        this.$refs.listbox.children[this.selected - 1].scrollIntoView({block: "nearest"})
      },

      onArrowDown() {
        this.selected = this.selected + 1 > this.optionCount ? 1 : this.selected + 1
        this.$refs.listbox.children[this.selected - 1].scrollIntoView({block: "nearest"})
      },

      ...options
    }
  }
}


window.app = new App()
window.hexpm_billing_checkout = app.billing_checkout
window.$ = $
window.liveSocket = liveSocket

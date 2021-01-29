// TODO: Remove dependencies to reduce, start with jquery

import "phoenix_html"
import { Socket } from "phoenix"
import LiveSocket from "phoenix_live_view"
import 'alpinejs'
import hljs from 'highlight.js/lib/highlight'
import elixir from 'highlight.js/lib/languages/elixir'

import "../css/app.css"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } })
liveSocket.connect()


window.autoResizeIframe = function(id) {
  var elem = document.getElementById(id);

  var newHeight = elem.contentWindow.document.body.scrollHeight;
  var newWidth = elem.contentWindow.document.body.scrollWidth;

  elem.height = (newHeight) + "px";
  elem.width = (newWidth) + "px";
}

window.Components = {
  listBox(options) {
    return {
      activeDescendant: null,
      optionCount: null,
      open: false,
      selected: null,
      value: 0,

      init() {
        this.optionCount = this.$refs.listbox.children.length

        this.$watch("selected", value => {
          if (!this.open) return

          if (this.selected === null) {
            this.activeDescendant = ""
            return
          }

          this.activeDescendant = this.$refs.listbox.children[this.selected].id
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
          this.$refs.listbox.children[this.selected].scrollIntoView({block: "nearest"})
        })
      },

      onOptionSelect() {
        if (this.selected !== null)
          this.vaule = this.selected

        this.$refs.listbox.children[this.selected].getElementsByTagName("a")[0].click()
        this.$refs.button.focus()
        this.open = false
      },

      onEscape() {
        this.open = false
      },

      onArrowUp() {
        this.selected = this.selected - 1 < 0 ? this.optionCount - 1 : this.selected - 1
        this.$refs.listbox.children[this.selected].scrollIntoView({block: "nearest"})
      },

      onArrowDown() {
        this.selected = this.selected + 1 >= this.optionCount ? 0 : this.selected + 1
        this.$refs.listbox.children[this.selected].scrollIntoView({block: "nearest"})
      },

      ...options
    }
  }
}


window.hexpmBillingCheckout = (token) => {
  fetch(window.hexpmBillingPostAction, {
    mode: "cors",
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({token: token, _csrf_token: window.hexpmBillingCsrfToken})
  })
  .then((response) => {
    if (response.ok) {
      // TODO: Success flash?
      window.location.reload()
    } else {
      response.json().then((json) => {
        document.getElementById("flash").innerHTML =
          '<div class="alert alert-danger" role="alert">' +
          '<strong>Failed to update payment method</strong><br>' +
          json.errors +
          '</div>'
      })
    }
  })
  .catch((error) => {
    document.getElementById("flash").innerHTML =
      '<div class="alert alert-danger" role="alert">' +
      '<strong>Network error when updating payment method</strong>' +
      '</div>'
    console.log(error)
  })
}

window.liveSocket = liveSocket

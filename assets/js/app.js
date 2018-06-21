// Brunch automatically concatenates all files in your
// watched paths. Those paths can be configured at
// config.paths.watched in "brunch-config.js".
//
// However, those files will only be executed if
// explicitly imported. The only exception are files
// in vendor, which are never wrapped in imports and
// therefore are always executed.

// Import dependencies
//
// If you no longer want to use a dependency, remember
// to also remove its path from "config.paths.watched".
import "phoenix_html"

// Import local files
//
// Local files can be imported directly using relative
// paths "./socket" or full ones "web/static/js/socket".

// import socket from "./socket"

export default class App {
  constructor() {
    // Copy button
    $(".copy-button").click(this.onCopy.bind(this))

    // Show show-versions button if JS is enabled
    $(".show-versions").show()

    // Package: toggle text in "All Versions / Recent Version" buttons
    $(".show-versions .invisible").removeClass("invisible").toggle()
    $(".show-versions .toggle-text").click((event) => $(event.target).parent().find("a").toggle())

    // Focus search field
    $("[name='search']").focus()

    // Switch tabs
    $(".nav-tabs a").click(function (e) {
      e.preventDefault()
      $(this).tab("show")
    })

    $("[data-toggle='popover']").popover({container: "body", html: true})

    // Highlight syntax
    hljs.initHighlightingOnLoad()
  }

  // Package: copy config snippet to clipboard
  onCopy(event) {
    var button = $(event.currentTarget)
    var succeeded = false

    try {
      var snippet = document.getElementById(button.attr("data-input-id"))
      snippet.select()
      succeeded = document.execCommand("copy")
    } catch (e) {
      console.log("snippet copy failed", e)
    }

    succeeded ? this.copySucceeded(button) : this.copyFailed(button)
  }

  copySucceeded(button) {
    button.children(".glyphicon-copy").hide()
    button.children(".glyphicon-ok").show()
    button.tooltip({title: "Copied!", container: "body", placement: "bottom", trigger: "manual"}).tooltip("show")

    setTimeout(() => {
      button.children(".glyphicon-ok").hide()
      button.children(".glyphicon-copy").show()
      button.tooltip("hide")
    }, 1500)
  }

  copyFailed(button) {
    button.children(".glyphicon-copy").hide()
    button.children(".glyphicon-remove").show()
    button.tooltip({title: "Copy not supported in your browser", container: "body", placement: "bottom", trigger: "manual"}).tooltip("show")

    setTimeout(() => {
      button.children(".glyphicon-remove").hide()
      button.children(".glyphicon-copy").show()
      button.tooltip("hide")
    }, 1500)
  }
}

new App()

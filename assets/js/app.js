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
    $(".snippet-copy-button").click(this.copySnippet.bind(this))

    $(".backup-copy-button").click(this.copyBackupCode.bind(this))
    $(".backup-download-button").click(this.downloadBackupCode.bind(this))

    // Show show-versions button if JS is enabled
    $(".show-versions").show()

    // Package: toggle text in "All Versions / Recent Version" buttons
    $(".show-versions .invisible").removeClass("invisible").toggle()
    $(".show-versions .toggle-text").click((event) => $(event.target).find("a").toggle())

    // Highlight syntax
    hljs.initHighlightingOnLoad()
  }

  // 2FA: Create a text file with backup codes and download
  downloadBackupCode(event) {
    var button = $(event.currentTarget)
    var text = button.attr('data-download-text')
    var el = document.createElement('a')

    el.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text))
    el.setAttribute('download', 'hex_backup_codes.txt')
    el.style.display = 'none'

    document.body.appendChild(el)
    el.click()
    document.body.removeChild(el)
  }

  // 2FA: Copy backup codes to the clipboard
  copyBackupCode(event) {
    var button = $(event.currentTarget)
    var el = document.createElement('textarea')

    el.value = button.attr('data-clipboard-text')
    el.setAttribute('readonly', '') // Prevent keyboard from showing on mobile
    el.style.contain = 'strict'
    el.style.all = 'unset'
    el.style.position = 'absolute'
    el.style.left = '-9999px'
    el.style.fontSize = '12pt' // Prevent zooming on iOS
    document.body.appendChild(el)
    el.select()

    let succeeded = false
    try {
      succeeded = document.execCommand('copy')
    } catch (err) {}

    document.body.removeChild(el)

    succeeded ? this.copySucceeded(button) : this.copyFailed(button)
  }

  // Package: copy config snippet to clipboard
  copySnippet(event) {
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

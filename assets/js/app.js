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

import $ from "jquery"
import "bootstrap"
import hljs from 'highlight.js/lib/highlight';
import elixir from 'highlight.js/lib/languages/elixir';


export default class App {
  constructor() {
    // Copy button
    $(".copy-button").click(this.onCopy.bind(this))

    // Pricing selector
    $(".pricing-button").click(this.onPricing.bind(this))

    // Focus username or search field
    if ($("#username").length > 0) {
      $("#username").focus()
    } else {
      $("[name='search']").focus()
    }

    // Switch tabs
    $(".nav-tabs a").click(function (e) {
      e.preventDefault()
      $(this).tab("show")
    })

    $("[data-toggle='popover']").popover({container: "body", html: true, animation: false})

    // Highlight syntax
    hljs.registerLanguage('elixir', elixir);
    hljs.initHighlightingOnLoad()

    //API permissions checkboxes
    $(".permission-group .group-owner input").change(function(){
      if (this.checked) {
        $(this).parents(".permission-group").find(".group-child label input").each(function(idx, value){ $(this).prop("disabled", true); $(this).prop("checked", true)})
      }else{
        $(this).parents(".permission-group").find(".group-child label input").each(function(idx, value){ $(this).prop("disabled", false); $(this).prop("checked", false)})
      }
    });
  }

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

  onPricing(event) {
    var button = $(event.currentTarget)
    $(".pricing .btn-selected").removeClass("btn-selected")
    button.addClass("btn-selected")

    if (button.text() === "Monthly") {
      $(".price.price-monthly").show()
      $(".price.price-yearly").hide()
    } else if (button.text() === "Yearly") {
      $(".price.price-monthly").hide()
      $(".price.price-yearly").show()
    }
  }

  billing_checkout(token) {
    $.post(window.hexpm_billing_post_action, {token: token, _csrf_token: window.hexpm_billing_csrf_token})
      .done(function (data) {
        window.location.reload()
      })
      .fail(function (data) {
        var response = JSON.parse(data.responseText);
        $('div.flash').html(
          '<div class="alert alert-danger" role="alert">' +
          '<strong>Failed to update payment method</strong><br>' +
          response.errors +
          '</div>'
        )
      })
  }
}

window.app = new App()
window.hexpm_billing_checkout = app.billing_checkout
window.$ = $

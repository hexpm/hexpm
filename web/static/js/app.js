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
import "deps/phoenix_html/web/static/js/phoenix_html"

// Import local files
//
// Local files can be imported directly using relative
// paths "./socket" or full ones "web/static/js/socket".

// import socket from "./socket"
//


// Highlight syntax
//

hljs.initHighlightingOnLoad();

// Package: copy config snippet to clipboard
function copy_snippet(element_id, button) {
  succeeded = false;
  try {
    snippet = document.getElementById(element_id);
    snippet.select();

    succeeded = document.execCommand('copy')
  } catch (e) {
    console.log('snippet copy failed', e);
  }

  if(succeeded) { copy_succeeded(button) }
  else { copy_failed(button); }
}

function copy_succeeded(button) {
  $(button).children().removeClass("glyphicon-copy").addClass("glyphicon-ok green");
  $(button).tooltip({ title: 'Copied!', container: 'body', placement: 'bottom', trigger: 'manual' }).tooltip('show');
  setTimeout(function() { $(button).children().removeClass("glyphicon-ok green").addClass("glyphicon-copy"); $(button).tooltip("hide")  }, 1500);
}

function copy_failed(button) {
  $(button).children().removeClass("glyphicon-copy").addClass("glyphicon-remove");
  $(button).tooltip({ title: 'Copy not supported in your browser', container: 'body', placement: 'bottom', trigger: 'manual' }).tooltip('show');
  setTimeout(function() { $(button).children().removeClass("glyphicon-remove").addClass("glyphicon-copy"); $(button).tooltip("hide")  }, 1500);
}

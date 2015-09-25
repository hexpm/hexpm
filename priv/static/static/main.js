// Show show-versions button if JS is enabled
$('.show-versions').show();

// Hide older versions on load
$('#versions li.older').collapse('hide');

// Package: toggle text in "All Versions / Recent Version" buttons
$('.show-versions .invisible').removeClass('invisible').toggle();
$('.show-versions .toggle-text').click(function() {
  $(this).find('span').toggle();
});

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

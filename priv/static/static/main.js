// Show show-versions button if JS is enabled
$('.show-versions').show();

// Hide older versions on load
$('#versions li.older').collapse('hide');

// Package: toggle text in "All Versions / Recent Version" buttons
$('.show-versions .invisible').removeClass('invisible').toggle();
$('.show-versions .toggle-text').click(function() {
  $(this).find('span').toggle();
});


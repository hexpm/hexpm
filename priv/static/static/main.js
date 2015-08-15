// Package: toggle text in "All Versions / Recent Version" buttons
$('.show-versions .invisible').removeClass('invisible').toggle();
$('.show-versions .toggle-text').click(function() {
  $(this).find('span').each(function() {
    $(this).toggle();
  });
});

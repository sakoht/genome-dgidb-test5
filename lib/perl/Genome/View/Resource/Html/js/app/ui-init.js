$(document).ready(
    function() {
        // apply jQueryUI styles to button elements
        $("a.button, input:submit, button").button();

        // draw last updated time

        if (document.cookie.indexOf("cacheon=1") >= 0) {
            $('#updatedOn').text($(document).data('updatedOn').toString()).easydate();

            $('#refreshCache').click(function() {
                var url = location.pathname.substr(5) + location.search;

                $.ajax({
                    url: '/cachetrigger' + url,
                    success: function(data) {
                        location.reload();
                    }
                });

                $(this).parent().parent().find('.cache_time p').replaceWith("<p style='margin-top: 12px;'><strong>Loading...</strong></p>");

                return false;
            });
        } else {
            $('.cache_info').hide();
        }
 
        // init masonry for view object container
        $('#objects').masonry(
            {
                columnWidth: 320,
                singleMode: true,
                itemSelector: '.span_8_box_masonry'
            }
        );

/*
        // set up control bar state & behavior
        $('#bar_menu, #bar_menu ul').hide();

        var barClosed = 1;

        $('#bar_base').mouseenter(function() {
            if (barClosed) {
                $('#bar_menu')
                    .show('fast', function() {
                        barClosed = 0;
                        $('#bar_menu ul').fadeIn('fast');
                    })
                    .mouseleave(function() {
                        var mouseBackOver = 0;
                        $(this).mouseenter(function(){ mouseBackOver = 1; });

                        // wait for a second to see if user hovers over menu again
                        setTimeout(function() {
                            if (!mouseBackOver) {
                            $('#bar_menu ul')
                                .fadeOut('fast', function(){
                                    $(this).parent()
                                        .hide('fast', function() {
                                            barClosed = 1;
                                        })
                                        .unbind();
                                });
                            }
                        }, 1000);
                    });
            }
        });
*/

    }
);

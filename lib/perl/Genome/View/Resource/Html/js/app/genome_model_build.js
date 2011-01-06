$(document).ready(function() {

    // init build process tabs
    $("#process_tabs").tabs({
        cache: false, // would be nice to cache, but if user navigates away from 
                      // the ajax tab while it is loading, it will refuse to load 
        spinner: '<img src="/res/img/spinner_e5e5e3.gif" width="16" height="16" align="middle"/>',
        ajaxOptions: {
            error: function(xhr, status, index, anchor) {
                $(anchor.hash).html("<p style='font-weight:bold;text-align:center;padding-top:35px'>Sorry, could not load workflow.</p>");
            }
        }
    });

    // rounded corners only on the top of our tab menu, thank you very much!
    $("#process_tabs ul").removeClass("ui-corner-all").addClass("ui-corner-top");

    $('a.popup').click(function() {
        var wObj = "obj" + this.title;
        var eventObject = window[wObj];

        // assemble event info into a table
        var popup_content = '<table class="boxy_info" cellpadding="0" cellspacing="0" border="0" width="300"><tbody>';
        for (prop in eventObject) {
            if (prop != 'popup_title') {
                popup_content += '<tr><td class="label">' + prop.replace(/_/g," ") + ':</td><td class="value">' + eventObject[prop] + '</td></tr>';
            }
        }

        popup_content += '</tbody></table>';

        var popup = $('<div id="event_popup_' + wObj + '">' + popup_content + '</div>').appendTo('body');

        popup.dialog({
            title: this.title,
            width: 550,
            height: 450
        });

        var dWidget = popup.dialog("widget");

        // tweak titlebar styles
        dWidget.find(".ui-dialog-titlebar").removeClass("ui-corner-all").addClass("ui-corner-top");
                                
        return false;
      });

});

function event_popup(eventObject) {

    // assemble event info into a table
    var popup_content = '<table class="boxy_info" cellpadding="0" cellspacing="0" border="0" width="300"><tbody>';
    for (prop in eventObject) {
        if (prop != 'popup_title') {
            popup_content += '<tr><td class="label">' + prop.replace(/_/g," ") + ':</td><td class="value">' + eventObject[prop] + '</td></tr>';
        }
    }

    popup_content += '</tbody></table>';

    // create popup
    var popup = new Boxy(popup_content, {title:eventObject.popup_title, fixed:false});
    popup.center();
}


$(function (){
    $('a.popup-ajax').click(function() {
        var url = this.href;
        var ptitle = this.title;
        var popup = $('<div id="event_popup"><p style="text-align: center; margin-top: 50px;"><img src="/res/img/spinner_ffffff.gif" width="16" height="16" align="absmiddle"/> Loading ' + ptitle + ' ...</p></div>').appendTo('body');

        popup.dialog({
            title: ptitle,
            width: 550,
            height: 450
        });

        var dWidget = popup.dialog("widget");

        // tweak titlebar styles
        dWidget.find(".ui-dialog-titlebar").removeClass("ui-corner-all").addClass("ui-corner-top");

        popup.load(url);

        return false;
    });
});



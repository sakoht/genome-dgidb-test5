$(document).ready(function() {

$('a.notes-popup').click(function() {
    var ptitle = this.title;
    var popup_selector = '#notes_subject_' + this.id;
    var popup = $("#notes_subject_" + this.id);

    popup.dialog({
        title: ptitle,
        width: 450,
        height: 250
    });

    var dWidget = popup.dialog("widget");

    // tweak titlebar styles
    dWidget.find(".ui-dialog-titlebar").removeClass("ui-corner-all").addClass("ui-corner-top");

    return false;
});

});
package UR::Object::Viewer::Toolkit::Gtk;

use warnings;
use strict;

our $VERSION = '0.1';

require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Toolkit',
    has => [
        toolkit_name    => { is_constant => 1, value => "gtk" },
        toolkit_module  => { is_constant => 1, value => "Gtk" },
    ]
);

sub show_viewer_modally {
    my $class = shift;
    my $viewer = shift;
    my $window = $class->create_window_for_viewer($viewer);
    return unless $window;
    $window->set_modal(1);
    $window->show_all;
    $window->signal_connect("destroy", sub { Gtk->main_quit });
    Gtk->main;
    return 1;
}

sub show_viewer {
    my $class = shift;
    my $viewer = shift;
    my $window = $class->create_window_for_viewer($viewer) or return;
    $window->show_all;
    return 1;
}

sub hide_viewer {
    my $class = shift;
    my $viewer = shift;
    $class->delete_window_around_viewer($viewer) or return;
    my $widget = $viewer->get_widget;
    $widget->hide();
    return 1;
}

our %open_editors;
sub create_window_for_viewer {
    my $class = shift;
    my $viewer = shift;
    
    my @params = @_;
    my %params = @_; #_compile_hash(@_);
    
    # Make a window for the viewer.
    my $win = new Gtk::Window;
    $win->set_title("test title");
    
    # Extract the widget underlying the viewer and put it in the window.
    my $widget = $viewer->get_widget;
    Carp::confess($widget) unless($widget);
    $win->add($widget);
    
    # Put the window in the hash of editors.
    my $subject = $viewer->get_subject();
    $open_editors{$viewer} = $win;
    
    # Show the editor.        
    $win->set_default_size(400,200);
    $win->show_all;

    # Destroy viewer if window is cloased.
    $win->signal_connect('delete_event', sub 
    {       
        if (App::UI->remove_window($win))
        {
            $class->delete_window_around_viewer($viewer);
            return 0;
        }
        else
        {
            return 1;
        }
    });
    
    # Add to the list of windows.
    App::UI::Gtk->add_window($win);
    
    # Return this.
    return $win;
}

sub delete_window_around_viewer {
    my $class = shift;
    my $viewer = shift;
    my $subject = $viewer->get_subject;
    my $widget = $viewer->get_widget;
    my $win = delete $open_editors{$viewer};
    $win->remove($widget);
    $win->destroy;
    App::UI::Gtk->remove_window($win);
    return 1;
}

1;


=pod

=head1 NAME

UR::Object::Viewer::Toolkit::Gtk - Declaration of Gtk as a Viewer toolkit type

=head1 SYNOPSIS

Methods called by UR::Object::Viewer to get toolkit specific support for
common tasks.

=cut



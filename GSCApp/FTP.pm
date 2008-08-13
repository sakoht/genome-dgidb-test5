# Manage uploading files to ftp server.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# set package name for module
package GSCApp::FTP;

=pod

=head1 NAME

GSCApp::FTP - manage uploading of files to GSC ftp server

=head1 SYNOPSIS

  use GSCApp;

  GSCApp::FTP->upload(dir => 'path/to/directory');
  GSCApp::FTP->upload(dir => 'another/directory', private => 1);

=head1 DESCRIPTION

This module is capable of automatically uploading directories to the
GSC FTP server.  This module is GSC specific and has no counterpart in
the App tree.

=cut

# set up package
require 5.6.0;
use warnings;
use strict;
our $VERSION = '0.3';
use base qw(App::MsgLogger);
use File::Basename;
use IO::Handle;

=pod

=head2 METHODS

The methods deal with managing files on the FTP server.

=over 4

=item upload

  GSCApp::FTP->upload(dir => 'path/to/dir');

This method take a directory and uploads it to the FTP server.  The
method takes a hash as an argument and returns the URL of the uploaded
directory upon success, C<undef> on failure.  The hash argument must
has a key named C<dir> whose value is the directory to upload.

=cut

sub upload
{
    my $class = shift;
    my %opts = @_;

    # make sure the directory was specified
    if (exists($opts{dir}))
    {
        $class->debug_message("hash key dir exists", 4);
    }
    else
    {
        $class->error_message("no directory specified");
        return;
    }
    my $path = $opts{dir};
    if ($path)
    {
        $class->debug_message("hash key dir defined: $path", 4);
    }
    else
    {
        $class->error_message("directory option given but value undefined");
        return;
    }

    # strip trailing slash
    $path =~ s{/+$}{};

    # make sure dir exists
    if (-e $path)
    {
        $class->debug_message("$path exists");
    }
    else
    {
        $class->warning_message("path does not exist: $path");
        next;
    }
    # and is a directory
    if (-d $path) {
        $class->debug_message("$path is a directory");
    }
    else {
        $class->warning_message("path must be a directory: $path");
        next;
    }

    # determine path
    my $target = $class->target . '/private';
    if (-d $target)
    {
        $class->debug_message("private ftp directory exists: $target", 4);
    }
    else
    {
        $class->error_message("private ftp directory does not exist: $target: $!");
        return;
    }
    if (-w $target)
    {
        $class->debug_message("private ftp directory is writable: $target", 4);
    }
    else
    {
        $class->error_message("private ftp directory is not writable: $target: $!");
        return;
    }

    # randomize the path
    my $rand;
    do
    {
        $rand = int(rand(1000000000000000));
    } while (-e "$target/$rand");
    $target .= "/$rand";
    if (mkdir($target))
    {
        $class->debug_message("created random subdirectory: $target", 4);
    }
    else
    {
        $class->error_message("failed to create random subdirectory:");
        return;
    }

    # copy it over
    my @cp = ('cp', '-r', $path, $target);
    if (system(@cp) == 0)
    {
        $class->debug_message("copy of $path to $target successful", 4);
    }
    else
    {
        $class->error_message("copy of $path to $target failed");
        return;
    }

    # construct and return url
    my $url = "$target/" . basename($path);
    my $bp  = $class->target;
    $url =~ s{^$bp}{ftp://genome.wustl.edu};
    return "$url/";
}

=item target

The ftp target directory.

PARAMS:
RETURNS: $target_directory


=cut

sub target {
  return '/gsc/var/lib/ftp';
}

=item notification

  GSCApp::FTP->upload(recipient => 'recipient@one.email.com,recipient@two.email.com',
                      url => 'http://put.url.address/string/here');

This method take a recipient email string and url string.  The
method takes a hash as an argument and returns boolean to indicate success or fail. 
 The hash argument must has key named C<recipient> to email the notification to
 and C<url_string> for the uploaded file location(s).

=cut

sub notification {
  my $proto = shift;
  my %params = @_;
  my $recipients = $params{recipient};
  my $url_string = $params{url_string};
  unless($recipients && $url_string) {
    App->error_message("recipient and url_string parameters must be specified!");
    return 0;
  }
  # create email
  my $email;
  # get email template
  my @templates = App::Path->find_files_in_path('email*', 'share', 'ftp-upload');
  foreach my $template (@templates) {
      my $fh = IO::File->new("<$template");
      if (defined($fh)) {
          App->debug_message("opened $template for reading", 2);
      }
      else {
          App->warning_message("failed to open $template for reading: $!");
          next;
      }
      $email = join('', $fh->getlines);
      $email .= "\n";
      $fh->close;

  }
  unless($email) {
    App->error_message("no message found!");
    return;
  }
  # insert url string into email
  chomp($url_string);
  $email =~ s/%URLS%/$url_string/;
  # send the mail
  my $rv = App::Mail->mail
  (
      To => $recipients,
      Subject => 'files ready on FTP site',
      Message => $email
  );
  if ($rv) {
      App->debug_message("sent mail to $recipients");
  }
  else {
      App->error_message("failed to send mail to $recipients");
      return 0;
  }
  return 1;
}

sub check_case_insensitive_dup_file {
   my $proto = shift;
   my $path = shift;
   my @list = split /\n/, `find $path -print`;
   my %h;
   foreach my $fn (@list) {
     chomp($fn);
     $h{lc($fn)} ++;
   }
   my $dupmesg = '';
   my $founddup = 0;
   foreach my $m (keys %h) { 
      if($h{$m} > 1) {
        $founddup ++; 
        $dupmesg .= $m . "\t" . $h{$m} ."\n"; 
      }
   }
   my $msg = '';
   if($founddup) {
     print STDERR "WARNING: Found duplicate filenames if the case is ignored.\n";
     print STDERR "         Please take extra care when downloading the files to the case insensitive OS. For example, Microsoft Window\n";
     print STDERR "Shown below is the duplicate filenames.\n";
     print STDERR $dupmesg;
     $msg = "WARNING: Found duplicate filenames if the case is ignored.\n";
     $msg .= "         Please take extra care when download the files to the case insensitive OS. For example, Microsoft Window\n";
     $msg .= "Shown below is the duplicate filenames.\n";
     $msg .= $dupmesg;
   }
   return ($founddup, $msg);
}

1;
__END__

=pod

=back

=head1 BUGS

Please report bugs to the software-support queue in RT.

=head1 SEE ALSO

App(3), GSCApp(3), App::Config(3), cp(1)

=head1 AUTHOR

David Dooling <ddooling@watson.wustl.edu>

=cut

# $HeadURL$
# $Id$

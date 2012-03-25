package Genome::Sys;

use strict;
use warnings;
use Genome;
use Cwd;
use File::Path;
use File::Spec;
use File::Basename;
use Carp;
use IO::File;

our $VERSION = $Genome::VERSION;

class Genome::Sys {};

#####
# API for accessing software and data by version
#####

sub snapshot_revision {
    my $class = shift;

    # Previously we just used UR::Util::used_libs_perl5lib_prefix but this did not
    # "detect" a software revision when using code from PERL5LIB or compile-time
    # lib paths. Since it is common for developers to run just Genome from a Git
    # checkout we really want to record what versions of UR, Genome, and Workflow
    # were used.

    my @orig_inc = @INC;
    my @libs = ($INC{'UR.pm'}, $INC{'Genome.pm'});
    die $class->error_message('Did not find both modules loaded (UR and Genome).') unless @libs == 2;

    # assemble list of "important" libs
    @libs = map { File::Basename::dirname($_) } @libs;
    push @libs, UR::Util->used_libs;

    # remove trailing slashes
    map { $_ =~ s/\/+$// } (@libs, @orig_inc);

    @libs = $class->_uniq(@libs);

    # preserve the list order as appeared @INC
    my @inc;
    for my $inc (@orig_inc) {
        push @inc, grep { $inc eq $_ } @libs;
    }

    @inc = $class->_uniq(@inc);

    # if the only path is like /gsc/scripts/opt/genome/snapshots/genome-1213/lib/perl then just call it genome-1213
    # /gsc/scripts/opt/genome/snapshots/genome-1213/lib/perl -> genome-1213
    # /gsc/scripts/opt/genome/snapshots/custom/genome-foo/lib/perl -> custom/genome-foo
    if (@inc == 1 and $inc[0] =~ /^\/gsc\/scripts\/opt\/genome\/snapshots\//) {
        $inc[0] =~ s/^\/gsc\/scripts\/opt\/genome\/snapshots\///;
        $inc[0] =~ s/\/lib\/perl$//;
    }

    return join(':', @inc);
}


sub _uniq {
    my $self = shift;
    my @list = @_;
    my %seen = ();
    my @unique = grep { ! $seen{$_} ++ } @list;
    return @unique;
}


sub dbpath {
    my ($class, $name, $version) = @_;
    unless ($version) {
        die "Genome::Sys dbpath must be called with a database name and a version. " .
            "Use 'latest' for the latest installed version.";
    }
    my $base_dirs = $ENV{"GENOME_DB"} ||= '/var/lib/genome/db';
    return $class->_find_in_path($base_dirs, "$name/$version");
}

sub _find_in_path {
    my ($class, $base_dirs, $subdir) = @_;
    my @base_dirs = split(':',$base_dirs);
    my @dirs =
        map { -l $_ ? Cwd::abs_path($_) : ($_) }
        map {
            my $path = join("/",$_,$subdir);
            (-e $path ? ($path) : ())
        }
        @base_dirs;
    return $dirs[0];
}

sub swpath {
    my ($class, $name, $version) = @_;
    unless ($version) {
        die "Genome::Sys swpath must be called with a database name and a version. " .
            "Use 'latest' for the latest installed version.";
    }
    my $base = $ENV{"GENOME_SW"} ||= '/var/lib/genome/sw';
    my $path = join("/",$base,$name,$version);
    if (-e $path) {
        return $path;
    }
    if ($path = `which $name$version`) {
        chomp $path;
        return $path;
    }
    if ($path = `which $name`) {
        chomp $path;
        $path = readlink($path) while -l $path;
        if ($version eq 'latest') {
            return $path;
        }
        else {
            die $class->error_message("Failed to find $name at version $version. " . 
                "The default version is at $path.");
        }
    }
    else {
        die $class->error_message("Failed to find $name at version $version!");
    }
    return;
}

#####
# Temp file management
#####

sub _temp_directory_prefix {
    my $self = shift;
    my $base = join("_", map { lc($_) } split('::',$self->class));
    return $base;
}

our $base_temp_directory;
sub base_temp_directory {
    my $self = shift;
    my $class = ref($self) || $self;
    my $template = shift;

    my $id;
    if (ref($self)) {
        return $self->{base_temp_directory} if $self->{base_temp_directory};
        $id = $self->id;
    }
    else {
        # work as a class method
        return $base_temp_directory if $base_temp_directory;
        $id = '';
    }

    unless ($template) {
        my $prefix = $self->_temp_directory_prefix();
        $prefix ||= $class;
        my $time = $self->__context__->now;

        $time =~ s/[\s\: ]/_/g;
        $template = "/gm-$prefix-$time-$id-XXXX";
        $template =~ s/ /-/g;
    }

    # See if we're running under LSF and LSF gave us a directory that will be
    # auto-cleaned up when the job terminates
    my $tmp_location = $ENV{'TMPDIR'} || "/tmp";
    if ($ENV{'LSB_JOBID'}) {
        my $lsf_possible_tempdir = sprintf("%s/%s.tmpdir", $tmp_location, $ENV{'LSB_JOBID'});
        $tmp_location = $lsf_possible_tempdir if (-d $lsf_possible_tempdir);
    }
    # tempdir() thows its own exception if there's a problem

    # For debugging purposes, allow cleanup to be disabled
    my $cleanup = 1;
    if($ENV{'GENOME_SYS_NO_CLEANUP'}) {
        $cleanup = 0;
    } 
    my $dir = File::Temp::tempdir($template, DIR=>$tmp_location, CLEANUP => $cleanup);

    $self->create_directory($dir);

    if (ref($self)) {
        return $self->{base_temp_directory} = $dir;
    }
    else {
        # work as a class method
        return $base_temp_directory = $dir;
    }

    unless ($dir) {
        Carp::croak("Unable to determine base_temp_directory");
    }

    return $dir;
}

our $anonymous_temp_file_count = 0;
sub create_temp_file_path {
    my $self = shift;
    my $name = shift;
    unless ($name) {
        $name = 'anonymous' . $anonymous_temp_file_count++;
    }
    my $dir = $self->base_temp_directory;
    my $path = $dir .'/'. $name;
    if (-e $path) {
        Carp::croak "temp path '$path' already exists!";
    }

    if (!$path or $path eq '/') {
        Carp::croak("create_temp_file_path() failed");
    }

    return $path;
}

sub create_temp_file {
    my $self = shift;
    my $path = $self->create_temp_file_path(@_);
    my $fh = IO::File->new($path, '>');
    unless ($fh) {
        Carp::croak "Failed to create temp file $path: $!";
    }
    return ($fh,$path) if wantarray;
    return $fh;
}

sub create_temp_directory {
    my $self = shift;
    my $path = $self->create_temp_file_path(@_);
    $self->create_directory($path);
    return $path;
}

#####
# Basic filesystem operations
#####

sub tar {
    my ($class, %params) = @_;
    my $tar_path = delete $params{tar_path};
    my $input_directory = delete $params{input_directory};
    my $input_pattern = delete $params{input_pattern};
    $input_pattern = '*' unless defined $input_pattern;

    if (%params) {
        Carp::confess "Extra parameters given to tar method: " . join(', ', sort keys %params);
    }

    unless ($tar_path) {
        Carp::confess "Not given path at which tar should be created!";
    }
    if (-e $tar_path) {
        Carp::confess "File exists at $tar_path, refusing to overwrite with new tarball!";
    }

    unless ($input_directory) {
        Carp::confess "Not given directory containing input files!";
    }
    unless (-d $input_directory) {
        Carp::confess "No input directory found at $input_directory";
    }

    my $current_directory = getcwd;
    unless (chdir $input_directory) {
        Carp::confess "Could not change directory to $input_directory";
    }

    if (Genome::Sys->directory_is_empty($input_directory)) {
        Carp::confess "Cannot create tarball for empty directory $input_directory!";
    }

    my $cmd = "tar -cf $tar_path $input_pattern";
    my $rv = Genome::Sys->shellcmd(
        cmd => $cmd,
    );
    unless ($rv) {
        Carp::confess "Could not create tar file at $tar_path containing files in " .
            "$input_directory matching pattern $input_pattern";
    }

    unless (chdir $current_directory) {
        Carp::confess "Could not change directory back to $current_directory";
    }
    return 1;
}

sub untar {
    my ($class, %params) = @_;
    my $tar_path = delete $params{tar_path};
    my $target_directory = delete $params{target_directory};
    my $delete_tar = delete $params{delete_tar};

    if (%params) {
        Carp::confess "Extra parameters given to untar method: " . join(', ', sort keys %params);
    }
    unless ($tar_path) {
        Carp::confess "Not given path to tar file to be untarred!";
    }
    unless (-e $tar_path) {
        Carp::confess "No file found at $tar_path!";
    }
    $target_directory = getcwd unless $target_directory;
    $delete_tar = 0 unless defined $delete_tar;

    my $current_directory = getcwd;
    unless (chdir $target_directory) {
        Carp::confess "Could not change directory to $target_directory";
    }

    my $rv = Genome::Sys->shellcmd(
        cmd => "tar -xf $tar_path",
    );
    unless ($rv) {
        Carp::confess "Could not untar $tar_path into $target_directory";
    }

    unless (chdir $current_directory) {
        Carp::confess "Could not change directory back to $current_directory";
    }

    if ($delete_tar) {
        unlink $tar_path;
    }

    return 1;
}

sub directory_is_empty {
    my ($class, $directory) = @_;
    my @files = glob("$directory/*");
    if (@files) {
        return 0;
    }
    return 1;
}

sub rsync_directory {
    my ($class, %params) = @_;
    my $source_dir = delete $params{source_directory};
    my $target_dir = delete $params{target_directory};
    my $pattern = delete $params{file_pattern};

    unless ($source_dir) {
        Carp::confess "Not given directory to copy from!";
    }
    unless (-d $source_dir) {
        Carp::confess "No directory found at $source_dir";
    }
    unless ($target_dir) {
        Carp::confess "Not given directory to copy to!";
    }
    unless (-d $target_dir) {
        Genome::Sys->create_directory($target_dir);
    }
    $pattern = '' unless $pattern;

    my $source = join('/', $source_dir, $pattern);
    my $rv = Genome::Sys->shellcmd(
        cmd => "rsync -rlHpgt $source $target_dir",
    );
    unless ($rv) {
        confess "Could not copy data matching pattern $source to $target_dir";
    }
    return 1;
}

sub line_count {
    my ($self, $path) = @_;
    my ($line_count) = qx(wc -l $path) =~ /^(\d+)/;
    return $line_count;
}

sub create_directory {
    my ($self, $directory) = @_;

    unless ( defined $directory ) {
        Carp::croak("Can't create_directory: No path given");
    }

    # FIXME do we want to throw an exception here?  What if the user expected
    # the directory to be created, not that it already existed
    return $directory if -d $directory;

    my $errors;
    # make_path may throw its own exceptions...
    File::Path::make_path($directory, { mode => 02775, group => 'info', error => \$errors });
    
    if ($errors and @$errors) {
        my $message = "create_directory for path $directory failed:\n";
        foreach my $err ( @$errors ) {
            my($path, $err_str) = %$err;
            $message .= "Pathname " . $path ."\n".'General error' . ": $err_str\n";
        }
        Carp::croak($message);
    }
    
    unless (-d $directory) {
        Carp::croak("No error from 'File::Path::make_path', but failed to create directory ($directory)");
    }

    return $directory;
}

sub create_symlink {
    my ($class, $target, $link) = @_;

    unless ( defined $target ) {
        Carp::croak("Can't create_symlink: no target given");
    }

    unless ( defined $link ) {
        Carp::croak("Can't create_symlink: no 'link' given");
    }

    unless ( -e $target ) {
        Carp::croak("Cannot create link ($link) to target ($target): target does not exist");
    }
    
    if ( -e $link ) { # the link exists and points to spmething
        Carp::croak("Link ($link) for target ($target) already exists.");
    }
    
    if ( -l $link ) { # the link exists, but does not point to something
        Carp::croak("Link ($link) for target ($target) is already a link.");
    }

    unless ( symlink($target, $link) ) {
        Carp::croak("Can't create link ($link) to $target\: $!");
    }
    
    return 1;
}

sub create_symlink_and_log_change {
    my $class  = shift || die;
    my $owner  = shift || die;
    my $target = shift || die;
    my $link   = shift || die;

    $class->create_symlink($target, $link);

    # create a change record so that if the databse change is undone this symlink will be removed
    my $symlink_undo = sub {
        $owner->status_message("Removing symlink ($link) due to database rollback.");
        unlink $link;
    };
    my $symlink_change = UR::Context::Transaction->log_change(
        $owner, 'UR::Value', $link, 'external_change', $symlink_undo
    );
    unless ($symlink_change) {
        die $owner->error_message("Failed to log symlink change.");
    }

    return 1;
}

sub read_file {
    my ($self, $fname) = @_;
    my $fh = $self->open_file_for_reading($fname);
    Carp::croak "Failed to open file $fname! " . $self->error_message() . ": $!" unless $fh;
    if (wantarray) {
        my @lines = $fh->getlines;
        return @lines;
    }
    else { 
        my $text = do { local( $/ ) ; <$fh> } ;  # slurp mode
        return $text;
    }
}

sub write_file {
    my ($self, $fname, @content) = @_;
    my $fh = $self->open_file_for_writing($fname);
    Carp::croak "Failed to open file $fname! " . $self->error_message() . ": $!" unless $fh;
    for (@content) {
        $fh->print($_) or Carp::croak "Failed to write to file $fname! $!";
    }
    $fh->close or Carp::croak "Failed to close file $fname! $!";
    return $fname;
}

sub _open_file {
    my ($self, $file, $rw) = @_;
    if ($file eq '-') {
        if ($rw eq 'r') {
            return 'STDIN';
        }
        elsif ($rw eq 'w') {
            return 'STDOUT';
        }
        else {
            die "cannot open '-' with access '$rw': r = STDIN, w = STDOUT!!!";
        }
    }
    my $fh = (defined $rw) ? IO::File->new($file, $rw) : IO::File->new($file);
    return $fh if $fh;
    Carp::croak("Can't open file ($file) with access '$rw': $!");
}

sub validate_file_for_reading {
    my ($self, $file) = @_;

    unless ( defined $file ) {
        Carp::croak("Can't validate_file_for_reading: No file given");
    }

    if ($file eq '-') {
        return 1;
    }

    unless (-e $file ) {
        Carp::croak("File ($file) does not exist");
    } 

    unless (-f $file) {
        Carp::croak("File ($file) exists but is not a plain file");
    }

    unless ( -r $file ) { 
        Carp::croak("Do not have READ access to file ($file)");
    }

    return 1;
}

sub open_file_for_reading {
    my ($self, $file) = @_;

    $self->validate_file_for_reading($file)
        or return;

    # _open_file throws its own exception if it doesn't work
    return $self->_open_file($file, 'r');
}

sub open_file_for_writing {
    my ($self, $file) = @_;

    $self->validate_file_for_writing($file)
        or return;

    if (-e $file) {
        unless (unlink $file) {
            Carp::croak("Can't unlink $file: $!");
        }
    }

    return $self->_open_file($file, 'w');
}

sub open_gzip_file_for_reading {
    my ($self, $file) = @_;

    $self->validate_file_for_reading($file)
        or return;

    #check file type for gzip or symlink to a gzip
    my $file_type = $self->_file_type($file);
    if ($file_type ne "gzip") {
        Carp::croak("File ($file) is not a gzip file");
    }

    my $pipe = "zcat ".$file." |";

    # _open_file throws its own exception if it doesn't work
    return $self->_open_file($pipe);
}

# Returns the file type, following any symlinks along the way to their target
sub _file_type {
    my $self = shift;
    my $file = shift;
        
    $self->validate_file_for_reading($file);
    $file = $self->follow_symlink($file);

    my $result = `file -b $file`;
    my @answer = split /\s+/, $result;
    return $answer[0];
}

# Follows a symlink chain to reach the final file, accounting for relative symlinks along the way
sub follow_symlink {
    my $self = shift;
    my $file = shift;

    # Follow the chain of symlinks
    while (-l $file) {
        my $original_file = $file;
        $file = readlink($file);
        # If the symlink was relative, repair that
        unless (File::Spec->file_name_is_absolute($file)) {
            my $path = dirname($original_file);
            $file = join ("/", ($path, $file));
        }
        $self->validate_file_for_reading($file);
    }

    return $file;
}

#####
# Methods dealing with user names, groups, etc
#####
sub user_id {
    return $<;
}

sub username {
    my $class = shift;
    my $username = $ENV{'REMOTE_USER'} || getpwuid($class->user_id);
    return $username;
}

sub sudo_username {
    my $class = shift;
    my $who_output = $class->cmd_output_who_dash_m || '';
    my $who_username = (split(/\s/,$who_output))[0] || '';
    my $sudo_username = $who_username eq $class->username ? '' : $who_username;
    $sudo_username ||= $ENV{'SUDO_USER'};
    return ($sudo_username || '');
}

sub current_user_is_admin {
    my $class = shift;
    return Genome::Sys->current_user_has_role('admin');
}

sub current_user_has_role {
    my ($class, $role_name) = @_;
    my $user = Genome::Sys::User->get(username => $class->username);
    return 0 unless $user;
    return $user->has_role_by_name($role_name);
}

sub cmd_output_who_dash_m {
    return `who -m`;
}

sub user_is_member_of_group {
    my ($class, $group_name) = @_;
    my $user = Genome::Sys->username;
    my $members = (getgrnam($group_name))[3];
    return ($members && $user && $members =~ /\b$user\b/);
}

#####
# Various utility methods
#####
sub open_browser {
    my ($class, @urls) = @_;
    for my $url (@urls) {
        if ($url !~ /:\/\//) {
            $url = 'http://' . $url; 
        }
    }
    my $browser;
    if ($^O eq 'darwin') {
        $browser = "open";
    }
    elsif ($browser = `which firefox`) {
        
    }
    elsif ($browser = `which opera`) {

    }
    for my $url (@urls) {
        Genome::Sys->shellcmd(cmd => "$browser $url");
    }
    return 1;
}

sub shellcmd {
    # execute a shell command in a standard way instead of using system()\
    # verifies inputs and ouputs, and does detailed logging...

    # TODO: add IPC::Run's w/ timeout but w/o the io redirection...

    my ($self,%params) = @_;
    my $cmd                          = delete $params{cmd};
    my $output_files                 = delete $params{output_files} ;
    my $input_files                  = delete $params{input_files};
    my $output_directories           = delete $params{output_directories} ;
    my $input_directories            = delete $params{input_directories};
    my $allow_failed_exit_code       = delete $params{allow_failed_exit_code};
    my $allow_zero_size_output_files = delete $params{allow_zero_size_output_files};
    my $allow_zero_size_input_files  = delete $params{allow_zero_size_input_files};
    my $skip_if_output_is_present    = delete $params{skip_if_output_is_present};
    my $dont_create_zero_size_files_for_missing_output = 
        delete $params{dont_create_zero_size_files_for_missing_output};
    my $print_status_to_stderr       = delete $params{print_status_to_stderr};

    $print_status_to_stderr = 1 if not defined $print_status_to_stderr;
    $skip_if_output_is_present = 1 if not defined $skip_if_output_is_present;
    if (%params) {
        my @crap = %params;
        Carp::confess("Unknown params passed to shellcmd: @crap");
    }
    # Go ahead and print the status message if the cmd is shortcutting
    if ($output_files and @$output_files) {
        my @found_outputs = grep { -e $_ } grep { not -p $_ } @$output_files;
        if ($skip_if_output_is_present
            and @$output_files == @found_outputs
        ) {
            $self->status_message(
                "SKIP RUN (output is present):     $cmd\n\t"
                . join("\n\t",@found_outputs)
            );
            return 1;
        }
    }
    my $old_status_cb = undef;
    unless  ($print_status_to_stderr) {
        $old_status_cb = Genome::Sys->message_callback('status');
        # This will avoid setting the callback to print to stderr
        # NOTE: we must set the callback to undef for the default behaviour(see below)
        Genome::Sys->message_callback('status',sub{});
    }

    if ($input_files and @$input_files) {
        my @missing_inputs;
        if ($allow_zero_size_input_files) {
            @missing_inputs = grep { not -e $_ } grep { not -p $_ } @$input_files;
        } else {
            @missing_inputs = grep { not -s $_ } grep { not -p $_ } @$input_files;
        }
        if (@missing_inputs) {
            Carp::croak("CANNOT RUN (missing input files):     $cmd\n\t"
                         . join("\n\t", map { -e $_ ? "(empty) $_" : $_ } @missing_inputs));
        }
    }

    if ($input_directories and @$input_directories) {
        my @missing_inputs = grep { not -d $_ } @$input_directories;
        if (@missing_inputs) {
            Carp::croak("CANNOT RUN (missing input directories):     $cmd\n\t"
                        . join("\n\t", @missing_inputs));
        }
    }

    $self->status_message("RUN: $cmd");
    my $exit_code = system($cmd);
    if ( $exit_code == -1 ) {
        Carp::croak("ERROR RUNNING COMMAND. Failed to execute: $cmd");
    } elsif ( $exit_code & 127 ) {
        my $signal = $exit_code & 127;
        my $withcore = ( $exit_code & 128 ) ? 'with' : 'without';

        Carp::croak("COMMAND KILLED. Signal $signal, $withcore coredump: $cmd");
    } elsif ($exit_code >> 8 != 0) {
        $exit_code = $exit_code >> 8;
        $DB::single = $DB::stopper;
        if ($allow_failed_exit_code) {
            Carp::carp("TOLERATING Exit code $exit_code, msg $! from: $cmd");
        } else {
            if($! eq 'No such file or directory') {
                for my $missing_input_file (grep { not -s $_ } @$input_files) {
                    $self->status_message("Missing file ($missing_input_file)");
                }
                for my $output_file (@$output_files) {
                    my $output_dir = (File::Basename::fileparse($output_file))[1];
                    if (not -d $output_dir) {
                        $self->status_message("Missing output dir ($output_dir)");
                    } elsif (not -s $output_file) {
                        $self->status_message("Missing output file ($output_file)");
                    }
                }
            }
            Carp::croak("ERROR RUNNING COMMAND.  Exit code $exit_code, msg $! from: $cmd");
        }
    }

    my @missing_output_files;
    if ($output_files and @$output_files) {
        @missing_output_files = grep { not -s $_ }  grep { not -p $_ } @$output_files;
    }
    if (@missing_output_files) {
        if ($allow_zero_size_output_files
            #and @$output_files == @missing_output_files
            # XXX This causes the command to fail if only a few of many files are empty, despite
            # that the option 'allow_zero_size_output_files' was given. New behavior is to warn
            # in either circumstance, and to warn that old behavior is no longer present in cases
            # where the command would've failed
        ) {
            if (@$output_files == @missing_output_files) {
                Carp::carp("ALL output files were empty for command: $cmd");
            } else {
                Carp::carp("SOME (but not all) output files were empty for command " . 
                    "(PLEASE NOTE that earlier versions of Genome::Sys->shellcmd " . 
                    "would fail in this circumstance): $cmd");
            }
            if ($dont_create_zero_size_files_for_missing_output) {
                @missing_output_files = (); # reset the list of missing output files
                @missing_output_files = 
                    grep { not -e $_ }  grep { not -p $_ } @$output_files; # rescan for only missing files
            } else {
                for my $output_file (@missing_output_files) {
                    Carp::carp("ALLOWING zero size output file '$output_file' for command: $cmd");
                    my $fh = $self->open_file_for_writing($output_file);
                    unless ($fh) {
                        Carp::croak("failed to open $output_file for writing to replace missing output file: $!");
                    }
                    $fh->close;
                }
                @missing_output_files = ();
            }
        }
    }
    
    my @missing_output_directories;
    if ($output_directories and @$output_directories) {
        @missing_output_directories = grep { not -s $_ }  grep { not -p $_ } @$output_directories;
    }


    if (@missing_output_files or @missing_output_directories) {
        for (@$output_files) { 
            if (-e $_) {
                unlink $_ or Carp::croak("Can't unlink $_: $!");
            }
        }
        Carp::croak("MISSING OUTPUTS! "
                    . join(', ', @missing_output_files)
                    . " "
                    . join(', ', @missing_output_directories));
    } 
    unless  ($print_status_to_stderr) {
        # Setting to the original behaviour (or default)
        Genome::Sys->message_callback('status',$old_status_cb);
    }
    return 1;    

}

1;

__END__

    methods => [
        dbpath => {
            takes => ['name','version'],
            uses => [],
            returns => 'FilesystemPath',
            doc => 'returns the path to a data set',
        },
        swpath => {
            takes => ['name','version'],
            uses => [],
            returns => 'FilesystemPath',
            doc => 'returns the path to an application installation',
        },
    ]

# until we get the above into ur...

=pod

=head1 NAME

Genome::Sys

=head1 VERSION

This document describes Genome::Sys version 0.05.

=head1 SYNOPSIS

use Genome;

my $dir = Genome::Sys->dbpath('cosmic', 'latest');

=head1 DESCRIPTION

Genome::Sys is a simple layer on top of OS-level concerns,
including those automatically handled by the analysis system, 
like database cache locations.

=head1 METHODS

=head2 swpath($name,$version)

Return the path to a given executable, library, or package.

This is a wrapper for the OS-specific strategy for managing multiple versions of software packages,
(i.e. /etc/alternatives for Debian/Ubuntu)

The GENOME_SW environment variable contains a colon-separated lists of paths which this falls back to.
The default value is /var/lib/genome/sw/.


=head2 dbpath($name,$version)

Return the path to the preprocessed copy of the specified database.
(This is in lieu of a consistent API for the database in question.)

The GENOME_DB environment variable contains a colon-separated lists of paths which this falls back to.
The default value is /var/lib/genome/db/.

=cut

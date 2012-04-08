#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Basename;
use IO::File;

# this is typically run from the top-level directory of a package
# just in case, chdir there
my $pkgdir = $FindBin::Bin;
chdir $pkgdir;

# find the package name from the parent directory name
my $name = $pkgdir;
chop($name) if $name =~ /\/$/;
$name =~ s|^.*/||;

# find the packaging directory from the script name
my $script = File::Basename::basename($FindBin::Script);
my $dir = $script;
$dir =~ s/-update.pl//;
unless (-d $dir) {
    die "no $dir found under $pkgdir!";
}
print "updating packaging in $dir\n";

# the debian-list file should contain the list of all packages to install in alpha order
my $path = $FindBin::Bin . "/$dir-list";
my $fh = IO::File->new($path);
$fh or die "failed to open file $path: $!";
my @lines = $fh->getlines;
chomp @lines;
my $list = join(",\n", map { '    ' . $_ } @lines);

# re-construct the debian/control file content
my $template = `cat $dir-control-template`;
my $new_content = eval '"' . $template . '"';

# see if the control file needs to be updated
my $old_control_path = $FindBin::Bin . "/$dir/control";
my $old_fh = IO::File->new($old_control_path);
$old_fh or die "failed to open temp file $old_control_path: $!";
my $old_content = join('',$old_fh->getlines);

if ($old_content eq $new_content) {
    print "Content matches for " . scalar(@lines) . " packages.  No updates.\n";
    exit;
}

# we only proceed if we need to change the control file
print "Updated packages...\n";

my $new_control_path = $old_control_path . '.new';
my $new_fh = IO::File->new('>' . $new_control_path);
$new_fh or die "failed to open temp file $new_control_path: $!";
$new_fh->print($new_content);
$new_fh->close;

# determine what message to put in the changelog 
my @diff = `sdiff -s $old_control_path $new_control_path`;
my @msg;
for my $change (@diff) {
    my ($old,$type,$new) = ($change =~ /^\s*(.*?)\s+([\<\|\>])\s+(.*)/);
    $old =~ s/,\s*$//;
    $new =~ s/,\s*$//;
    if ($type eq '<') {
        push @msg, "  * removed: $old";
    }
    elsif ($type eq '>') {
        push @msg, "  * added: $new";
    }
    else {
        push @msg, "  * changed: $old to $new"
    }
}
my $msg = join("\n",@msg);
print "MSG:\n---\n$msg\n---\n";

# note the last changelog entry
my $old_changelog_path = $FindBin::Bin . "/$dir/changelog";
my $latest_entry = `head -n 1 $old_changelog_path`;
print "Latest changelog entry is: $latest_entry\n";

# construct determine the version number, which will be the date, with an incrementing integer for multiple builds on the same day 
use Date::Format;
my $t = time();
my $date1 = Date::Format::time2str(q|%Y.%m.%d|,$t);
my $n = 1;
for (1) {
    my @conflicts = `grep "^$name ($date1-$n)" '$old_changelog_path'`;
    if (@conflicts) {
        print "FOUND PREVIOUS BUILD FROM TODAY: @conflicts\n";
        $n++;
        if ($n > 100) {
            die "this script is tired of rebuilding this package today";
        }
        redo;
    }
    else {
        print "No changelog entry found for $date1-$n.  Latest entry is $latest_entry"
    }
}

# create the new changelog entry
my $date2 = Date::Format::time2str(q|%a, %d %b %Y %H:%M:%S %z|,$t);
my $changelog_addition = <<EOS;
$name ($date1-$n) unstable; urgency=low

$msg

 -- The Genome Institute <gmt\@genome.wustl.edu>  $date2

EOS
my $new_changelog_addition_path = $old_changelog_path . '.new-entry';
my $new_changelog_addition_fh = IO::File->new('>' . $new_changelog_addition_path);
$new_changelog_addition_fh or die "failed to open $new_changelog_addition_path for writing! $!";
$new_changelog_addition_fh->print($changelog_addition);
$new_changelog_addition_fh->close;

my $new_changelog_path = $old_changelog_path . '.new';

for my $cmd (
    "cat $new_control_path >| $old_control_path",
    "rm $new_control_path",
    "cat $new_changelog_addition_path $old_changelog_path > $new_changelog_path",
    "rm $new_changelog_addition_path",
    "cat $new_changelog_path >| $old_changelog_path",
    "rm $new_changelog_path",
    "git diff $old_control_path",
    "git diff $old_changelog_path",
) {
    print "RUN: $cmd\n";
    my $rv = system $cmd; 
    $rv /= 256;
    if ($rv) {
        die "ERROR: $!"
    }
}



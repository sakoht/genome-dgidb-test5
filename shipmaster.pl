#!/usr/bin/env perl

print "WARNING: this is in development and not ready to run yet.\n*** It will mess with your repo so Ctry-C now. ***\n";

my @c = (
    'git checkout master',
    'git stash',
    'git fetch origin',
    'git pull origin master',
    'git checkout shipit',
    'git pull origin shipit',
    'git merge master',
    ['git status -s | grep ^DD', 'git rm'],
    ['git status -s | grep ^\ U', 'git add'],
    ['git status -s | grep ^AA', 'git rm'],
    [
        'find lib',  
        qr|lib/perl/Genome/Model/Tools/Music|,      'genome-music/lib/Genome/Model/Tools/Music',
        qr|lib/perl/Genome/Model/Tools/Sv|,         'genome-music/lib/Genome/Model/Tools/Sv',
        qr|lib/perl/Genome/Model/Tools/Annotate|,   'genome-music/lib/Genome/Model/Tools/Annotate',
        qr|lib/perl/Genome/Model/Tools/|,           'gmt-unsorted/lib/Genome/Model/Tools/',
        qr|lib/perl/Genome/Model/|,                 'genome-model-unsorted/lib/Genome/Model/',
        qr|lib/perl/Genome/Config/|,                'genome-site-wugc-perl/',
        qr|lib/perl/Genome/DataSource/|,            'genome-subject/lib/Genome/DataSource/', 
        qr|lib/perl/Genome/xsl/|,                   'genome-subject/xsl/',
        qr|lib/perl/Genome/Env/|,                   'genome/lib/Genome/Env/',
        qr|lib/perl/Genome.pm|,                     'genome/lib/Genome.pm',
    ],
    ['echo "COMMIT UNPLACED?" 1>&2; find lib -type f', 'git add'],
    ['echo "CLEANUP DIRS?" 1>&2; find lib -type d', 'rmdir'],
    'git commit -m "merged master"',
    'git push origin shipit',
    'git checkout master',
    'git stash pop',
);

for my $c (@c) {
    print "\n\n";
    if (ref($c) and @$c == 2) {
        # a command to get files, and a command to run on them
        run_on_files(@$c)
    }
    elsif (ref($c) and @$c > 2) {
        # a command to run get files, a regex to rename
        rename_files(@$c);
    }
    else {
        # a plain command to run
        run($c)
    }
}

sub run_on_files {
    my $f = shift;
    my $c = shift;
    print "FILES: $f\n";
    my @f = `$f`;
    print @f;
    chomp @f;
    if (@f == 0) {
        print "(none)\n";
        return;
    }
    for (@f) {
        s/^..\s+//;
    }
    my $cmd = $c . ' ' . join(" ", map { "'$_'" } @f), "\n";
    run($cmd);
}

sub rename_files {
    my $cmd_to_get_files = shift;
    my $find = shift;
    my $replace = shift;

    print "FILES: $cmd_to_get_files\n";
    my @f = `$cmd_to_get_files`;
    print @f;
    chomp @f;
    if (@f == 0) {
        print "(none)\n";
        return;
    }
    my @patterns;
    my %moved;
    while ($find and $replace) {
        print "  RENAME: $find TO: $replace\n";
        push @patterns, $find;
        for my $o (@f) {
            next if $moved{$o};
            my $n = $o;
            $n =~ s|$find|$replace|;
            if ($n ne $o) { 
                if (-d $o) {
                    if (-d $n) {
                        print "  # directory exists: $n\n";
                    }
                    else {
                        print "  # creating directory $n\n";
                        mkdir $n;
                    }
                } 
                else { 
                    $moved{$o} = $n;
                    run(qq|git mv "$o" "$n"\n|); 
                }
            }
        }
        # get the next set of expressions
        $find = shift @_;
        $replace = shift @_;
    }
    my @f2 = `$cmd_to_get_files`;
    if (@f2) {
        print "UNMOVED FILES: @f2\n";
    }
}

sub run {
    my $c = shift;
    print "RUN: $c [Y(es)|s(kip)|a(bort)]\n";
    my $a = <>;
    chomp $a;
    if ($a eq 's') {
        print "(skipped)\n";
    }
    elsif ($a eq 'y' or $a eq '') {
        print "(running...)\n";
        my $r = system $c;
        print "exit code $r\n";
    }
    else {
        print "aborting\n";
        exit 1;
    }
}


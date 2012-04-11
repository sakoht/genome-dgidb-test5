#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;

my $path = __FILE__;
my $dir = File::Basename::dirname($path);
chdir "$dir/..";

unless (@ARGV) {
    die "Usage: auto-integrate.pl SOMPKG\n";
}

unless (-e "$ENV{HOME}/.github-username") {
    die "Put your github username in ~/.github-username!\n";
}

my $user_github = `cat ~/.github-username`;
chomp $user_github;
if ($user_github) {
    print "got github username $user_github\n";
}
else {
    die "no github username at ~/.github-username";
}

warn "*** this is a very experimental attempt to automate R repackaging for TGI ...it will interact with github and git on your behalf, perhaps poorly (ctrl-c now) ***\n";
sleep 5;

for my $r_pkg (@ARGV) {
    my @possible_deb_pkgs = (
        'r-cran-' . lc($r_pkg),
        'r-bioc-' . lc($r_pkg),
    );
    my $deb_pkg_name;
    my $deb_version;
    for my $possible_deb_pkg (@possible_deb_pkgs) {
        print "checking for $possible_deb_pkg...\n";
        my ($line) = `dpkg -l $possible_deb_pkg | grep $possible_deb_pkg`;
        print "got $line\n";
        my ($pattern,$possilbe_deb_pkg_name, $possible_version, $desc) = split(/\s+/,$line);
        print "version is $possible_version\n";
        if ($possible_version) {
            $deb_pkg_name = $possible_deb_pkg;
            $deb_version = $possible_version;
            last;
        }
    }

    my $src_path = '';
    if (not $deb_pkg_name) {
        print "failed to find package for $r_pkg\n";
        my $tgz = `wget -q -O - http://cran.r-project.org/web/packages/$r_pkg/index.html | grep "Package source"`;
        unless ($tgz) {
            die "failed to find $r_pkg at cran.r-project.org/web/packages/$r_pkg/index.html";
        }
        chomp $tgz;
        print "tgz $tgz\n";
        $tgz =~ s/^.*\/([^\/]+?.tar.gz).*$/$1/;
        print "tgz $tgz\n";
        my $url = "http://cran.r-project.org/src/contrib/$tgz";
        print "URL is $url\n";
        system "cd /tmp; wget $url";
        $src_path = "/tmp/$tgz";
        if (-e $src_path) {
            print "got file $src_path\n";
        }
        else {
            print "no file at $src_path!\n";
        }
        $deb_pkg_name = 'r-cran-' . lc($r_pkg);
        $deb_version = lc($tgz);
        $deb_version =~ s/$r_pkg//;
        $deb_version =~ s/^_//;
        $deb_version =~ s/.tar.gz$//;
    }
    else {
        print "got $deb_pkg_name\n";
    }

    my $tmp = "tmp-mkdir";
    my @cmds = (
        #"mkdir $tmp",
        "chmod +rwx $tmp",
    );

    if (-d "vendor/$deb_pkg_name") {
        print "found submoudle at vendor/$deb_pkg_name...n";
        push @cmds, (
            \"chdir 'vendor/$deb_pkg_name'",
        );
    }
    else {
        print "no submoudle found at vendor/$deb_pkg_name ...creating...\n";
        print <<EOS;
****** open this URL: https://github.com/repositories/new
****** make a repo called $deb_pkg_name in your own namespace $user_github
EOS
        $DB::single = 1;
        if (`wget -O -q - https://github.com/genome-vendor/$deb_pkg_name 2>&1 | grep 'HTTP.* 404 Not Found'`) {
            print "not on github under genome-vendor yet\n";
            if (not `wget -O - -q https://github.com/$user_github/$deb_pkg_name 2>&1 | grep 'clone_url'`) {
                print "also no personal github repo for $user_github.  creating one...\n";
                push @cmds, (
                    "mkdir $tmp/$deb_pkg_name",
                    "chmod +rwx $tmp/$deb_pkg_name",
                    \"chdir '$tmp/$deb_pkg_name';",
                    "git init",
                    "touch README",
                    "git add README",
                    "git commit -m 'first commit'",
                    "git remote add origin git\@github.com:$user_github/$deb_pkg_name.git",
                    "git push -u origin master",
                    \"chdir '../..'",
                    "rm -rf $tmp/$deb_pkg_name",
                );
            }
            push @cmds, (
                \"\$nn=0; while (`wget -O -q - https://github.com/genome-vendor/$deb_pkg_name 2>&1 | grep 'HTTP.* 404 Not Found'`) { warn q|waiting for https://github.com/genome-vendor/$deb_pkg_name|; sleep 5 }",
            );
        }

        push @cmds, (
            "git submodule add git\@github.com:genome-vendor/$deb_pkg_name.git vendor/$deb_pkg_name",
            "git commit -m 'added empty repo/submodule for $deb_pkg_name linking to github/genome-vendor'",
        );
    }
    
    my $tmp2 = 'tmpsrc';
    my $short_name = lc($r_pkg);
    push @cmds, (
        \"chdir 'vendor/$deb_pkg_name'",
        "mkdir $tmp2", # this is another one _inside_the repo
    );

    if ($src_path) {
        # make new deb source
        push @cmds, (
            "cd $tmp2; mv $src_path .; tar -zxvf *.gz",
            "rm $tmp2/*.gz",
            "mv $tmp2/*/* .",
            "rmdir $tmp2/*/",
            "rmdir $tmp2",
            "cp -r ../../genome-snapshot-deps-r/example-debian-dir debian",
            "~ssmith/bin/findreplace PACKAGE_NAME $deb_pkg_name debian/*",
            "~ssmith/bin/findreplace VERSION '$deb_version'",
        );
    }
    else {
        # unpack exising deb source
        push @cmds, (
            "cd $tmp2; apt-get source $deb_pkg_name",
            "rm $tmp2/*.gz $tmp/*.dsc",
            "mv $tmp2/*/* .",
            "rmdir $tmp2/*/",
            "rmdir $tmp2",
        );
    }

    push @cmds, (
        "git checkout -b b$deb_version",
        "git add *",
        "git status",
        "git commit -m 'imported source for $deb_pkg_name' *",
        \"chdir 'vendor/$deb_pkg_name/'",
        \"unless (-e 'NAMESPACE') { system q|cp ../../genome-snapshot-deps-r/DEFAULT_NAMESPACE NAMESPACE; git add NAMESPACE; git commit -m add\\ NAMESPACE;| }",
        "git push origin b$deb_version",
        "dpkg-buildpackage; ls ../$deb_pkg_name*.changes", # ignore bad exit code on build package, just look for the .changes file
        \"chdir '..'",
        "dpkg -i *$short_name*.deb",
        "debsign -k$ENV{MYGPGKEY} *$short_name*.changes",
        "chmod 664 ${deb_pkg_name}_* ${short_name}_*",
        "chgrp info ${deb_pkg_name}_* ${short_name}_*",
        "mv ${deb_pkg_name}_* ${short_name}_*  ~codesigner/incoming/lucid-genome-development/",
        "ls -lt ~codesigner/incoming/lucid-genome-development/",
        "git add $deb_pkg_name",
        "git commit -m 'built $deb_pkg_name version $deb_version'",
        "git push origin master",
        "rm -rf $deb_pkg_name/.* $deb_pkg_name/*",
        \"chdir '..'",
        "echo '$deb_pkg_name (>= $deb_version)' >> genome-snapshot-deps-r/debian-list",
        "echo '$r_pkg' >> genome-snapshot-deps-r/base-list",
        "echo 'library($r_pkg)' >> genome-snapshot-deps-r/test.R",
    );

    my $n = 0;
    for my $cmd (@cmds) {
        if (ref($cmd)) {
            my $p = $$cmd;
            print "EVAL: $p\n";
            $DB::single = 1;
            eval $p;
             if ($@) {
                warn $@;
                $n++;
                if ($n > 10) {
                    die "giving up after $n tries\n";
                }
                sleep 5;
                redo;
             }
            next;
        }
        print "RUN: $cmd\n";
        $DB::single = 1;
        my $rv = system $cmd;
        $rv /= 256;
        if ($rv) {
            warn "ERROR: $!\n";
            $n++;
            if ($n > 10) {
                die "giving up after $n tries\n";
            }
            sleep 5;
            redo;
        }
        $n=0;
    }
}

__END__

        "#git commit -m 'replaced the namespace file with the R default' NAMESPACE",

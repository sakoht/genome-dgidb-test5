package Genome::Model::Command::Services::WebApp::Core;

# loads the majority of the base system used (not tools)

use File::Find;
use Genome;

our @error_classes;

my $imported = 0;
sub import {
    return 1 if $imported;
    $imported = 1;
    my @classes = ();

    # destroy args from plackup command line
    # so they dont interact with anything else
    undef @ARGV;

    my $base_dir = Genome->base_dir;
    find(
        sub {
            my $position = length($File::Find::name) - 3;
            return if (index($File::Find::name, '.pm', $position) != $position);
            return if (index($File::Find::name, 'Genome/Model/Tools') >= 0);
            return if (index($File::Find::name, 'Test.pm') >= 0);
            return if (index($File::Find::dir, '.d') >= 0);

            my $name = 'Genome' . substr($File::Find::name, length($base_dir));
            $name =~ s/\//::/g;
            substr($name, index($name, '.pm'), 3, '');

            push @classes, $name;
        },
        $base_dir
    );
    unless (@classes) {
        warn "There were no classes to load!";
    }

    @error_classes = grep {
        my $r = 0;
        if ($_ !~ /^Genome::(Model::Alignment|Utility::MetagenomicClassifier|Assembly)/) {
            eval "use $_";
            $r = $@;
        }
        $r;
    } @classes;

    warn "The following classes loaded with errors:\n  " .
        join ("\n  ",@error_classes)
        if (@error_classes);
    1;
}

1;

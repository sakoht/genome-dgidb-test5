package Genome::Model::Tools::Maq::Vmerge;

use strict;
use warnings;

use above "Genome";
use Command;
use File::Temp;
use IO::File;

class Genome::Model::Tools::Maq::Vmerge {
    is => 'Command',
    has => [ 
            'maplist'   => { is => 'list',      doc => "maplist file",},
            'pipe'      => { is => 'String',      doc => "the named pipe",      is_optional => 1},
            'tmp_script' => { is => 'String',     doc => "temp script to run",  is_optional => 1},
    ],
};

sub help_brief {
    "create a named pipe as output of maq mapmerged";
}

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS 
This takes a list of map files and creates a named pipe which streams the results of maq mapmerge.
EOS
}

sub create {
    my $class = shift;
    $DB::single = 1;
    my $self = $class->SUPER::create(@_);


    unless (defined ($self->tmp_script)){
        my ($out_fh,$tmp_script) = File::Temp::tempfile;
        $out_fh->close;
        unlink $tmp_script;
        $self->tmp_script($tmp_script);
    }
    
    unless (defined ($self->pipe)){
        my ($fh_pipe,$filename_pipe) = File::Temp::tempfile;
        $fh_pipe->close;
        unlink $filename_pipe;
        $self->pipe($filename_pipe);
    }

    return $self;
}

sub execute {
    my $self = shift;

    $DB::single=1;

    #my $maq_cmd = $self->maq_cmd();
    my $maq_pathname = '/gscuser/abrummet/maq-0.6.6/maq';

    my $maplist = $self->maplist;

    my @maplist;
    if (ref($maplist) eq 'ARRAY') {
        @maplist = @{$maplist};
    } else {
        @maplist = ($maplist);
    }

    unless (-p $self->pipe) {
        if (-e $self->pipe) {
            $self->error_message("File already exists ". $self->pipe .":  $!");
            return;
        } else {
            require POSIX;
            unless (POSIX::mkfifo($self->pipe, 0700)) {
                $self->error_message("Can not create named pipe ". $self->pipe .":  $!");
                return;
            }
        }
    }

    
    my $out_fh = IO::File->new($self->tmp_script,'w');
    unless ($out_fh) {
        $self->error_message("Can not write to file ". $self->tmp_script .":  $!");
        return;
    }

    print $out_fh "mapmerge\n";
    print $out_fh $self->pipe ."\n";

    for my $maplist (@maplist) {
        my $in_fh = IO::File->new($maplist,'r');
        unless($in_fh) {
            $self->error_message("Can not open file for reading '$maplist':  $!");
            return;
        }
        my @maps = <$in_fh>;
        $in_fh->close;
        print $out_fh @maps;
    }
    $out_fh->close;

    my @args = ($maq_pathname, 'runscript', $self->tmp_script);
    #print STDERR "Running command: @args\n";
    my $linkage_class = $self->c_linkage_class();
    my $function = $linkage_class . '::mapmergenozip';
    no strict 'refs';
    my $rv = $function->(@args);
    use strict 'refs';
    #my $rv = system(@args);
    #if ($rv) {
    #    $self->error_message("nonzero exit code returned by maq, command looks like, @args");
    #    return;
    #}
    return 1;
}

sub DESTROY {
    my $self = shift;
    unlink $self->pipe;
    unlink $self->tmp_script;
}

1;



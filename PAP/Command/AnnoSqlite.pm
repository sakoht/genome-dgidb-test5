#$Id: KEGGScan.pm 53220 2009-11-19 19:25:24Z josborne $

package PAP::Command::AnnoSqlite;

use strict;
use warnings;

use Workflow;

use Compress::Bzip2;
use English;
use File::Basename;
use File::chdir;
use File::Temp;
use IO::File;
use IPC::Run;
use Carp;


class PAP::Command::AnnoSqlite {
    is  => ['PAP::Command'],
    has => [
            locus_tag => { 
                           is => 'SCALAR',
                           doc => 'locus tag name',
                         },
            datecode => { is => 'SCALAR',
                          doc => 'date stamp code',
                        },
            workdir => { is => 'SCALAR',
                         doc => 'working directory that execution should take place in',
                       },
            success => { is => 'SCALAR',
                         doc => 'success flag',
                         is_optional => 1,
                       },
        ],
};

operation PAP::Command::AnnoSqlite {
    input        => ['locus_tag','datecode','workdir' ],
    output       => [ 'success' ],
    lsf_queue    => 'long',
    lsf_resource => '-R \'select[mem>8192 && type==LINUX64] rusage[mem=8192,tmp=100]\' -M 8192000 ',
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Run run the BER anno-sqlite.bash script";
}

sub help_synopsis {
    return <<"EOS"
EOS
}

sub help_detail {
    return <<"EOS"
Need documenation here.
EOS
}

sub execute {

    my $self = shift;


    ##FIXME:  This should not be hardcoded.  At least not here.  
    my $annosqlite = $self->workdir . "/anno-sqlite.bash";
    my @anno_command = (
                            $annosqlite,
                            $self->locus_tag,
                            $self->datecode,
                           );
    
    my ($anno_stdout, $anno_stderr);
    

    {
    
        local $CWD = $self->workdir();

        IPC::Run::run(
                      \@anno_command,
                      '<',
                      \undef,
                      '>',
                      \$anno_stdout,
                      '2>',
                      \$anno_stderr,
                     ) || croak "annosqlite failed: $anno_stderr : $CHILD_ERROR";
                     
    }
    
    
    return 1;

}



1;

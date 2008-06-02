package Genome::Model::Tools::Maq::FilterVariations;

use above "Genome";

class Genome::Model::Tools::Maq::FilterVariations {
    is => 'Genome::Model::Tools::Maq',
    has => [
        input => {
            type => 'String',
            doc => 'File path for input map',
        },
        snpfile => {
            type => 'String',
            doc => 'File path for snp file',
        },      
    ],
};

sub help_brief {
    "remove extra reads which are likely to be from the same fragment based on alignment start site, quality, and sequence",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gt remove-pcr-artifacts orig.map new_better.map removed_stuff.map --sequence-identity-length 26
EOS
}

sub help_detail {                           
    return <<EOS 
This tool removes reads from a maq map file which are likely to be the result of PCR, rather than distinct DNA fragments.
It examines all reads at the same start site, selects the read which has the best data to represent the group based on length and alignment quality.

A future enhancement would group reads with a common sequence in the first n bases of the read and select the best read from that group.
EOS
}

sub execute {
    $DB::single = 1;
    my $self = shift;
    my $in = $self->input;
    my $keep = $self->snpfile;
    unless ($in and $snpfile and -f $in and -f $snpfile) {
        $self->error_message("Bad params!");
        $self->usage_message($self->help_usage_complete_text);
        return;
    }
    
    my $result;
    $result = Genome::Model::Tools::Maq::FilterVariations_C::filter_variations($in,$snpfile);
    
    $result = !$result; # c -> perl

    $self->result($result);
    return $result;
}

package Genome::Model::Tools::Maq::FilterVariations_C;

our $inline_dir;
our $cflags;
our $libs;
BEGIN
{
    ($inline_dir) = "$ENV{HOME}/".(`uname -m` =~ /ia64/ ? '_InlineItanium' : '_Inline32');
    mkdir $inline_dir;
    $cflags = `pkg-config glib-2.0 --cflags`;
    $libs = `pkg-config glib-2.0 --libs`;
        
};

use Inline 'C' => 'Config' => (
            DIRECTORY => $inline_dir,
            INC => '-I./ovsrc -I/gscuser/jschindl/svn/gsc/zlib-1.2.3',
            CCFLAGS => `uname -m` =~ /ia64/ ? '-D_FILE_OFFSET_BITS=64 '.$cflags:'-D_FILE_OFFSET_BITS=64 -m32 '.$cflags,
            LIBS => '-L/gscuser/jschindl/svn/gsc/zlib-1.2.3 -lz '.$libs,
            NAME => __PACKAGE__
            );

use Inline C => <<'END_C';
#include "ovsrc/snplist.c"
#include "ovsrc/maqmap.c"
#include "ovsrc/ov.c" 
#include "ovsrc/dedup.c"
#include "ovsrc/bfa.c"
#include "ovsrc/ovc_test.c"

int filter_variations(char *mapfilename,char *snpfilename)
{
    return ovc_filter_variations(mapfilename,snpfilename);
}

END_C

1;

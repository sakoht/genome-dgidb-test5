package Genome::Model::Tools::Sam;

use strict;
use warnings;

use Genome; 
use File::Basename;
use POSIX;

my $DEFAULT = 'r544';
#3Gb
my $DEFAULT_MEMORY = 402653184;

class Genome::Model::Tools::Sam {
    is  => 'Command',
    has => [
        use_version => { 
            is  => 'Version', 
            doc => "samtools version to be used, default is $DEFAULT. ", 
            is_optional   => 1, 
            default_value => $DEFAULT,   
        },
        maximum_memory => {
            is => 'Integer',
            doc => "the maximum memory available, default is $DEFAULT_MEMORY",
            is_optional => 1,
            default_value => $DEFAULT_MEMORY,
        },
    ],
};

sub sub_command_sort_position { 12 }

sub help_brief {
    "Tools to run Sam or work with its output files.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools Sam ...    
EOS
}

sub help_detail {                           
    return <<EOS 
More information about the Sam suite of tools can be found at http://Samtools.sourceforege.net.
Everytime when we get a new version of samtools, we need update in this module and create new 
processing_profile/model for pipeline.
EOS
}


my %SAMTOOLS_VERSIONS = (
    r783    => '/gsc/pkg/bio/samtools/samtools-0.1.9/samtools',
    r613    => '/gsc/pkg/bio/samtools/samtools-0.1.8/samtools',
    r599    => '/gsc/pkg/bio/samtools/samtools-0.1.7ar599/samtools',
    r544    => '/gsc/pkg/bio/samtools/samtools-0.1.7ar544/samtools',
    r510    => '/gsc/pkg/bio/samtools/samtools-0.1.7a/samtools',
    r453    => '/gsc/pkg/bio/samtools/samtools-0.1.6/samtools',
    r449    => '/gsc/pkg/bio/samtools/samtools-0.1.5-32/samtools',
    r301wu1 => '/gscuser/dlarson/samtools/r301wu1/samtools',
    r320wu1 => '/gscuser/dlarson/samtools/r320wu1/samtools',
    r320wu2 => '/gscuser/dlarson/samtools/r320wu2/samtools',
    r350wu1 => '/gscuser/dlarson/samtools/r350wu1/samtools',
);

sub path_for_samtools_version {
    my ($class, $version) = @_;
    $version ||= $DEFAULT;
    my $path = $SAMTOOLS_VERSIONS{$version};
    return $path if defined $path;
    die 'No path found for samtools version: '.$version;
}

sub default_samtools_version {
    die "default samtools version: $DEFAULT is not valid" unless $SAMTOOLS_VERSIONS{$DEFAULT};
    return $DEFAULT;
}    
    
sub samtools_path {
    my $self = shift;
    return $self->path_for_samtools_version($self->use_version);
}

sub samtools_pl_path {
    my $self = shift;
    my $dir  = dirname $self->samtools_path;
    my $path = "$dir/misc/samtools.pl";
    
    unless (-x $path) {
        $self->error_message("samtools.pl: $path is not executable");
        return;
    }
    return $path;
}

sub c_linkage_class {
    my $self = shift;

$DB::single = $DB::stopper;
    my $version = $self->use_version;
    $version =~ s/\./_/g;

    my $class_to_use = __PACKAGE__ . "::CLinkage$version";
  
    #eval "use above '$class_to_use';";
    eval "use $class_to_use;";
    if ($@) {
        $self->error_message("Failed to use $class_to_use: $@");
        return undef;
    }

    return $class_to_use;
}

sub open_bamsam_in {
    my $self = shift;
    my $in_filename = shift;
    my ($type) = ($in_filename =~ /\.([^\.\s]+)\s*$/i);
    $type = uc($type);
    my $fh;
    if($type eq 'BAM') {
        $fh = new IO::File;
        #$fh->open('samtools view -h "' . $in_filename . '" | head -n 2000000 |');
        $fh->open('samtools view -h "' . $in_filename . '" |');
    }
    elsif($type eq 'SAM') {
        $fh = IO::File->new($in_filename);
    }
    else {
        die 'Unknown type specified for "' . $in_filename . "\".\n";
    }
    unless($fh) {
        die 'Failed to open "' . $in_filename . "\"\n.";
    }
    return $fh;
}

sub open_bamsam_out {
    my $self = shift;
    my $out_filename = shift;
    my ($type) = ($out_filename =~ /\.([^\.\s]+)\s*$/i);
    $type = uc($type);
    my $fh;
    if($type eq 'BAM') {
        $fh = new IO::File;
        $fh->open('| samtools view -S -b /dev/stdin > "' . $out_filename . '"');
    }
    elsif($type eq 'SAM') {
        $fh = IO::File->new($out_filename eq '-' ? stdout : '> ' . $out_filename);
    }
    else {
        die 'Unknown type specified for "' . $out_filename . "\".\n";
    }
    unless($fh) {
        die 'Failed to open "' . $out_filename . "\"\n.";
    }
    return $fh;
}

1;

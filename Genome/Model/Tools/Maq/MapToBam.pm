package Genome::Model::Tools::Maq::MapToBam;

use strict;
use warnings;

use Genome;
use File::Copy;
use File::Basename;

class Genome::Model::Tools::Maq::MapToBam {
    is  => 'Genome::Model::Tools::Maq',
    has => [ 
        map_file    => { 
            is  => 'String',      
            doc => 'name of map file',
        }
    ],
    has_optional => [
        lib_tag     => {
            is  => 'String',
            doc => 'library name used in sam/bam file to identify read group',
            default => '',
        },
        ref_list    => {
            is  => 'String',
            doc => 'ref list contains ref name and its length',
            default => '/gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/ref_list_for_bam',
        },
        index_bam   => {
            is  => 'Boolean',
            doc => 'flag to index bam file',
            default => 1,
        },
        keep_sam    => {
            is  => 'Boolean',
            doc => 'flag to keep sam file',
            default => 0,
        },
        fix_mate    => {
            is  => 'Boolean',
            doc => 'fix mate info problem in sam/bam',
            default => 0,
        },
    ],
};


sub help_brief {
    "create bam file from maq map file";
}


sub help_detail {
    return <<EOS 
This tool makes sam/bam file from maq map file with options to index bam file, keep sam file and use library tags. if maq version is below than 0.70, use maq2sam-short to convert, otherwise use maq2sam-long.
EOS
}


sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    $self->error_message('Map file not existing') and return unless -s $self->map_file;
    $self->error_message('Ref list not existing') and return unless -s $self->ref_list;
      
    return $self;
}


sub execute {
    my $self = shift;

    my $tool_path  = '/gscuser/dlarson/src/samtools/tags/samtools-0.1.2';
    my $tosam_path = $tool_path.'/misc/maq2sam-';
    my $samtools   = $tool_path.'/samtools';

    my ($ver) = $self->use_version =~ /^\D*\d\D*(\d)\D*\d/;
    $self->error_message("Give correct maq version") and return unless $ver;
    $tosam_path = $ver < 7 ? $tosam_path.'short' : $tosam_path.'long';

    my $map_file = $self->map_file;
    my ($root_name) = basename $map_file =~ /^(\S+)\.map/;
    
    my $map_dir  = dirname $map_file;
    my $sam_file = $map_dir . "/$root_name.sam";
    my $bam_file = $map_dir . "/$root_name.bam";

    my $cmd = sprintf('%s %s %s > %s', $tosam_path, $map_file, $self->lib_tag, $sam_file);
    my $rv  = system $cmd;
    $self->error_message("$cmd failed") and return if $rv or !-s $sam_file;
    
    $cmd = sprintf('%s import %s %s %s', $samtools, $self->ref_list, $sam_file, $bam_file);
    $self->status_message("MapToBam conversion command: $cmd");
    $rv  = system $cmd;
    $self->error_message("$cmd failed") and return if $rv or !-s $bam_file;
     
    #watch out disk space, for now hard code maxMemory 200000000 
    if ($self->fix_mate) {
        my $tmp_file = $bam_file.'.sort';
        $rv = system "$samtools sort -n -m 2000000000 $bam_file $tmp_file";
        $self->error_message("first sort failed") and return if $rv or !-s $tmp_file.'.bam';

        $rv = system "$samtools fixmate $tmp_file.bam $tmp_file.fixmate";
        $self->error_message("fixmate failed") and return if $rv or !-s $tmp_file.'.fixmate';
        unlink "$tmp_file.bam";

        $rv = system "$samtools sort -m 2000000000 $tmp_file.fixmate $tmp_file.fix";
        $self->error_message("Second sort failed") and return if $rv or !-s $tmp_file.'.fix.bam';
        
        unlink "$tmp_file.fixmate";
        unlink $bam_file;

        move "$tmp_file.fix.bam", $bam_file;
    }

    if ($self->index_bam) {
        $rv = system "$samtools index $bam_file";
        $self->error_message('Indexing bam_file failed') and return if $rv;
    }

    unlink $sam_file unless $self->keep_sam;
    return 1;
}

1;

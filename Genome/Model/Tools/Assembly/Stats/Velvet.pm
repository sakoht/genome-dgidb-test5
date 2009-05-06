package Genome::Model::Tools::Assembly::Stats::Velvet;

use strict;
use warnings;

use Genome;
use Cwd;
use Data::Dumper;

class Genome::Model::Tools::Assembly::Stats::Velvet {
    is => ['Genome::Model::Tools::Assembly::Stats'],
    has => [
	    first_tier => {
		type => 'int non_neg',
		is_optional => 1,
		doc => "first tier value",
	        },
	    second_tier => {
		type => 'int non_neg',
		is_optional => 1,
		doc => "second tier value",
	        },
	    assembly_directory => {
		type => 'String',
		is_optional => 1,
		doc => "path to assembly",
		},
	    major_contig_length => {
		type => 'int non_neg',
		is_optional => 1,
		doc => "Major contig length cutoff",
	        },
	    out_file => {
		type => 'String',
		is_optional => 1,
		doc => "Stats output file name",
	        },
	    ],
};

sub help_brief {
    'Run stats on velvet assemblies'
}

sub help_detail {
    return <<"EOS"
Run stats on velvet assemblies
EOS
}

sub execute {
    my ($self) = @_;
    my $stats;
    unless ($self->resolve_data_directory()) {
	$self->error_message("Unable to resolve data directory");
	return;
    }

    #SIMPLE READ STATS
    my ($s_stats, $five_k_stats, $content_stats) = $self->get_simple_read_stats();
    $stats .= $s_stats;
    print $s_stats;

    #CONTIGUITY STATS
    my $contiguity_stats = $self->get_contiguity_stats;
    $stats .= $contiguity_stats;
    print $contiguity_stats;

    #CONSTRAINT STATS
    my $constraint_stats = $self->get_constraint_stats();
    $stats .= $constraint_stats;
    print $constraint_stats;

    #GENOME CONTENTS
    $stats .= $content_stats;
    print $content_stats;

    #GENE CORE SURVEY STATS
    my $core_survey = $self->get_core_gene_survey_results();
    $stats .= $core_survey;
    print $core_survey;

    #READ DEPTH STATS
    my $ace = `ls -t velvet_asm.ace* | grep -v base_depth | head -1`;
    chomp $ace;
    unless ($ace) {
	$self->error_message("Can not file any velvet_asm.ace ace files");
	return;
    }
    my $depth_stats = $self->get_read_depth_stats($ace);
    $stats .= $depth_stats;
    print $depth_stats;

    #FIVE KB CONTIG STATS
    $stats .= $five_k_stats;
    print $five_k_stats;

    if ($self->out_file) {
	my $out_file = $self->out_file;
	my $fh = IO::File->new(">$out_file") || die;
	$fh->print($stats);
	$fh->close;
    }

    print "############\n##  DONE  ##\n############\n";

    return 1;
}

1;

package Genome::Model::Tools::Somatic::KsFilterGold;

use strict;
use warnings;

use Genome;
use Command;
use IO::File;
use File::Path;

class Genome::Model::Tools::Somatic::KsFilterGold {
    is => 'Command',
    has => [
    somatic_build_id => { 
        type => 'String',
        is_optional => 0,
        doc => "build id of the build to process",
    },
    output_data_dir => {
        type => 'String',
        is_optional => 0,
        doc => 'directory to store assembly results in',
    },
    _bamreadcount_executable => {
        type => 'String',
        is_optional => 0,
        doc => 'executable of the bam readcount program to use',
        default => '/gscuser/dlarson/src/bamsey/readcount/trunk/bam-readcount-test2',
    },
    _kstest_executable => {
        type => 'String',
        is_optional => 0,
        doc => 'executable of the ks test program to run',
        default => '/gscuser/dlarson/src/bamsey/kstest/trunk/bam-ks-test',
    },
    gold_snp_file=>{
    	type => 'String',
    	is_optional => 0,
    	doc => 'gold_snp file in tumor model',
    },
    ]
};


sub execute {
    my $self=shift;
    $DB::single = 1;
    my $build_id = $self->somatic_build_id;

    my $build = Genome::Model::Build->get($build_id);
    unless(defined($build)) {
        $self->error_message("Unable to find build $build_id");
        return;
    }
    my $model = $build->model;
    unless(defined($model)) {
        $self->error_message("Somehow this build does not have a model");
        return;
    }
    unless($model->type_name eq 'somatic') {
        $self->error_message("This build must be a somatic pipeline build");
        return;
    }

    #satisfied we should start doing stuff here
    my $data_directory = $build->data_directory;

    unless(-d $data_directory) {
        $self->error_message("$data_directory is not a directory");
        return;
    }

    my $tumor_bam = $build->tumor_build->whole_rmdup_bam_file;
    my $normal_bam = $build->normal_build->whole_rmdup_bam_file;
    my $gold_snp = $self->gold_snp_file;

    #first create the genotype file for reference distribution generation
    my $snpfh = IO::File->new($gold_snp);
    unless($snpfh) {
        $self->error_message("Unable to open $gold_snp for reading");
        return;
    }

    #spit out the regions into a file for posterity
    my $germline_het_pos_file = $self->output_data_dir . "/germline_hets_used_for_reference.pos";
    my $snp_outfh = IO::File->new($germline_het_pos_file,"w");
    unless($snp_outfh) {
        $self->error_message("Unable to write positions file for the reference distribution");
        return;
    }

    #gold snp file looks like below (unfortunately)
=cut
    1       554484  554484  C       C       ref     ref     ref     ref
    1       557616  557616  A       A       ref     ref     ref     ref
    1       711153  711153  G       G       ref     ref     ref     ref
    1       730720  730720  G       G       ref     ref     ref     ref
    1       742429  742429  A       A       SNP     SNP     SNP     SNP
    1       751595  751595  T       T       SNP     SNP     SNP     SNP
    1       755132  755132  A       A       ref     ref     ref     ref
    1       766985  766985  T       T       SNP     SNP     SNP     SNP
    1       775852  775852  C       C       SNP     SNP     SNP     SNP
    1       782343  782343  T       T       SNP     SNP     SNP     SNP
=cut
    
    while(my $line = $snpfh->getline()) {
        next unless($line =~ /ref/ && $line =~ /SNP/);#skip homozygous sites
        chomp $line;
        my @fields = split /\t/, $line;
        next unless($fields[3]=~ /[ACTG]/ && $fields[4] =~ /[ACTG]/);   #skip non genotype lines
        #in general want about 10000 sites to make it through
        #for now just downsample using perl under the assumption that the resulting distribution is representative
        next unless(rand() < 0.15);
        print $snp_outfh join("\t",@fields[0..2]),"\n";
    }
    $snp_outfh->close;
    $snpfh->close;

    my $user = $ENV{USER};

    #ok launch generation of the distribution
    my $distribution_file = $self->output_data_dir . "/germline.hets.var.dist";
    my $command = sprintf("bsub -N -u $user\@watson.wustl.edu -R 'select[type==LINUX64]' '%s -b 2 -q 1 -d -l %s -f /gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa %s | perl /gscuser/dlarson/src/bamsey/kstest/trunk/bam-readcount-dist-to-3p-var-dist.pl > %s'",$self->_bamreadcount_executable,$germline_het_pos_file,$tumor_bam,$distribution_file);

    print "$command\n";
    my ($distribution_lsf_id_line) = `$command`;
    my ($distribution_job) = $distribution_lsf_id_line =~ /<(\d+)>/;



    #assemble list of variants to filter. Let's filter all variants and then extrapolate the tiers etc
    #we need annotation output
    my $variants_file = $build->somatic_workflow_input('annotate_output_snp');
    my $kstest_file = $self->output_data_dir . "/kstest.csv";
    my $filtered_file = $self->output_data_dir . "/annotated_snp.ksandhomopolymer.filtered";
    
    #launch kstest
    my $kscmd = sprintf("bsub -N -u $user\@watson.wustl.edu -R 'select[type==LINUX64]' -w 'ended($distribution_job)' '%s -q 1 -l %s -d %s -f /gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa %s | tee %s | perl /gscuser/dlarson/src/bamsey/kstest/trunk/ks_and_strand_filter.pl | perl /gscuser/dlarson/src/bamsey/kstest/trunk/homopolymer_filter.pl > %s'",$self->_kstest_executable,$variants_file, $distribution_file, $tumor_bam, $kstest_file, $filtered_file);
    my ($ks_filter_lsf_line) = `$kscmd`;
    
        
    my $tumor_counts_file = $self->output_data_dir . "/tumor.counts";
    my $tumor_mm_file = $self->output_data_dir . "/tumor.counts.mm";

    my $tumor_readcount_cmd = sprintf("bsub -N -u $user\@watson.wustl.edu -R 'select[type==LINUX64]' '%s -q 1 -l %s -f /gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa %s | tee %s | perl /gscuser/dlarson/src/bamsey/kstest/trunk/bam-readcount-to-mm.pl > %s'",$self->_bamreadcount_executable,$variants_file,$tumor_bam,$tumor_counts_file,$tumor_mm_file);
    print $tumor_readcount_cmd,"\n";    
    my ($tumor_readcount_lsf_line) = `$tumor_readcount_cmd`;
        
    my $normal_counts_file = $self->output_data_dir . "/normal.counts";
    my $normal_mm_file = $self->output_data_dir . "/normal.counts.mm";

    my $normal_readcount_cmd = sprintf("bsub -N -u $user\@watson.wustl.edu -R 'select[type==LINUX64]' '%s -q 1 -l %s -f /gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa %s | tee %s | perl /gscuser/dlarson/src/bamsey/kstest/trunk/bam-readcount-to-mm.pl > %s'",$self->_bamreadcount_executable,$variants_file,$normal_bam,$normal_counts_file,$normal_mm_file);
    print $normal_readcount_cmd,"\n";
    my ($normal_readcount_lsf_line) = `$normal_readcount_cmd`;

    #paralog filter
    my ($tumor_mm_lsf_id) = $tumor_readcount_lsf_line =~ /<(\d+)>/;
    my ($normal_mm_lsf_id) = $normal_readcount_lsf_line =~ /<(\d+)>/;
    my ($ks_lsf_id) = $ks_filter_lsf_line =~ /<(\d+)>/;

    my $pass_paralog_filter_file = $self->output_data_dir . "/pass_paralog";

    my $fully_filtered_file = $self->output_data_dir . "/pass_all_filters";
    
    my $paralog_cmd = sprintf("bsub -N -u $user\@watson.wustl.edu -w 'ended($tumor_mm_lsf_id) && ended($normal_mm_lsf_id) && ended($ks_lsf_id)' 'perl /gscuser/dlarson/src/bamsey/kstest/trunk/paralog_filter.pl %s %s > %s; /gscuser/dlarson/bin/perl-grep-f -f %s %s > %s'",$tumor_mm_file, $normal_mm_file, $pass_paralog_filter_file,$pass_paralog_filter_file, $filtered_file,$fully_filtered_file);
    my ($paralog_lsf_line) = `$paralog_cmd`;
    my ($paralog_lsf_id) = $paralog_lsf_line =~ /<(\d+)>/;

    #do tiering, should probably be a function or something
    my $intersect_string = "bsub -N -u $user\@watson.wustl.edu -w 'ended($paralog_lsf_id)' '/gscuser/dlarson/bin/perl-grep-f -f %s %s > %s'";
    my $tier1_file = $build->somatic_workflow_input('tier_1_snp_file');
    my $tier1_filtered_file = $self->output_data_dir . "/t1f_tier1_filtered_snp.csv";
    my $intersect_command = sprintf($intersect_string,$tier1_file,$fully_filtered_file,$tier1_filtered_file);
    `$intersect_command`;

    my $tier1hc_file = $build->somatic_workflow_input('tier_1_snp_high_confidence_file');
    my $tier1hc_filtered_file = $self->output_data_dir . "/hf1_tier1_filtered_snp_high_confidence.csv";
    $intersect_command = sprintf($intersect_string,$tier1hc_file,$fully_filtered_file,$tier1hc_filtered_file);
    `$intersect_command`;


    my $tier2_file = $build->somatic_workflow_input('tier_2_snp_file');
    my $tier2_filtered_file = $self->output_data_dir . "/t2f_tier2_filtered_snp.csv";
    $intersect_command = sprintf($intersect_string,$tier2_file,$fully_filtered_file,$tier2_filtered_file);
    `$intersect_command`;

    my $tier2hc_file = $build->somatic_workflow_input('tier_2_snp_high_confidence_file');
    my $tier2hc_filtered_file = $self->output_data_dir . "/hf2_tier2_filtered_snp_high_confidence.csv";
    $intersect_command = sprintf($intersect_string,$tier2hc_file,$fully_filtered_file,$tier2hc_filtered_file);
    `$intersect_command`;


    my $tier3_file = $build->somatic_workflow_input('tier_3_snp_file');
    my $tier3_filtered_file = $self->output_data_dir . "/t3f_tier3_filtered_snp.csv";
    $intersect_command = sprintf($intersect_string,$tier3_file,$fully_filtered_file,$tier3_filtered_file);
    `$intersect_command`;

    my $tier3hc_file = $build->somatic_workflow_input('tier_3_snp_high_confidence_file');
    my $tier3hc_filtered_file = $self->output_data_dir . "/hf3_tier3_filtered_snp_high_confidence.csv";
    $intersect_command = sprintf($intersect_string,$tier3hc_file,$fully_filtered_file,$tier3hc_filtered_file);
    `$intersect_command`;

    my $tier4_file = $build->somatic_workflow_input('tier_4_snp_file');
    my $tier4_filtered_file = $self->output_data_dir . "/t4f_tier4_filtered_snp.csv";
    $intersect_command = sprintf($intersect_string,$tier4_file,$fully_filtered_file,$tier4_filtered_file);
    `$intersect_command`;

    my $tier4hc_file = $build->somatic_workflow_input('tier_4_snp_high_confidence_file');
    my $tier4hc_filtered_file = $self->output_data_dir . "/hf4_tier4_filtered_snp_high_confidence.csv";
    $intersect_command = sprintf($intersect_string,$tier4hc_file,$fully_filtered_file,$tier4hc_filtered_file);
    `$intersect_command`;
    
    return 1;

}


1;

sub help_brief {
    "Filters somatic snvs"
}

sub help_detail {
    <<'HELP';
    This runs some filters on predictions of the somatic pipeline and spits the results in a directory
HELP
}

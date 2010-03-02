package Genome::Model::Build::ReferenceAlignment::Solexa;

#REVIEW fdu
#Short:
#1. An indelpe filter should be added to _unsorted_indel_file to filter out output with 3rd column - and . after maq indelpe run to
#reduce the size of indel file that will be fed to gmt snp sort. Sometimes gmt snp sort will fail because of memory issue caused by too
#many lines of indel
#2. Current maq-maq pipeline generates filtered.indelpe.snps by _snv_file_filtered method during run_reports stage, which make no sense.
#That bunch of codes: maq SNPFilter -F <> under _snv_file_filtered really should be moved to G::M::C::B::ReferenceAlignment::Maq along with 
#method _indel_file and _unsorted_indel_file
#
#Long:
#1. Many maq-specific methods exist and there is need to make this module more generic to handle other aligners/variant-callers. 
#2. Some obsolete methods should be removed especially with maq dying out, like map_list_file_paths.
#3. Some methods can be shrunk by removing maq-related logic.
#4. Some methods (like those variant-related ones) in this module that are duplicates with those in G::M::ReferenceAlignment should be removed 
#or moved up to G::M::RefAlign. Just ask model for the methods when needed.


use strict;
use warnings;

use Genome;
use GSCApp;

class Genome::Model::Build::ReferenceAlignment::Solexa {
    is => 'Genome::Model::Build::ReferenceAlignment',
    has => [],

};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    unless ($self) {
        return;
    }

    my $model = $self->model;

    my @idas = $model->instrument_data_assignments;

    unless (scalar(@idas) && ref($idas[0])  &&  $idas[0]->isa('Genome::Model::InstrumentDataAssignment')) {
        $self->error_message('No instrument data have been added to model: '. $model->name);
        $self->error_message("The following command will add all available instrument data:\ngenome model instrument-data assign  --model-id=".
        $model->id .' --all');
        return;
    }

    return $self;
}

sub calculate_estimated_kb_usage {
    my $self = shift;
    my $model = $self->model;
    my $reference_build = $model->reference_build;
    my $reference_file_path = $reference_build->full_consensus_path;

    my $du_output = `du -sk $reference_file_path`;
    my @fields = split(/\s+/,$du_output);
    my $reference_kb = $fields[0];
    my $estimate_from_reference = $reference_kb * 30;

    my @idas = $model->instrument_data_assignments;
    my $estimate_from_instrument_data = scalar(@idas) * 10000;

    #return ($estimate_from_reference + $estimate_from_instrument_data);
    my $temporary_value = 31457280; # 30GB  -----> old #629145600; #600GB

    my $processing_profile_name = $model->processing_profile_name;

    if ($processing_profile_name =~ /alignments only/i) {
        $temporary_value = 10240; #10 MiB
    }
    
    return $temporary_value; 
}


sub calculate_input_base_counts_after_trimq2 {
    my $self = shift;
    my @idas = $self->instrument_data_assignments;
    my ($total_ct, $total_trim_ct) = (0, 0);

    for my $ida (@idas) {
        my ($ct, $trim_ct) = $ida->alignment->calculate_base_counts_after_trimq2;
        return unless $ct and $trim_ct;
        $total_ct += $ct;
        $total_trim_ct += $trim_ct;
    }

    return ($total_ct, $total_trim_ct);
}


sub consensus_directory {
    my $self = shift;
    return $self->data_directory .'/consensus';
}

sub _consensus_files {
    return shift->_files_for_pattern_and_optional_ref_seq_id('%s/consensus/%s.cns',@_);
}

sub bam_pileup_file_path {
    my $self = shift; 
    my $filename = $self->consensus_directory . "/all_sequences.cns.samtools_pileup";
    return $filename; 
}

sub bam_pileup_bzip_file_path {
    my $self = shift; 
    my $filename = $self->bam_pileup_file_path.".bz2";
    return $filename; 
}

sub bam_pileup_file {

    my $self = shift;
    my $file = $self->bam_pileup_file_path;
    my $bzip_file = $file.".bz2";
    if (-s $file) {
        return $file;
    } 
    elsif (-s $bzip_file) {
        #see if the bzip version exists
        my $pileup_file = Genome::Utility::FileSystem->bunzip($bzip_file);
        if (-s $pileup_file) {
            return $pileup_file;
        } 
        else {
            $self->error_message("Could not bunzip pileup file: $pileup_file.");
            die "Could not bunzip pileup file: $pileup_file.";
        }
    } 
    else {
        $self->error_message("No bam pileup file could be found at: $file.");
        die "No bam pileup file could be found at: $file."; 
    }

    return;
}

# TODO: we should abstract the genotyper the way we do the aligner
# for now these are hard-coded maq-ish values.

sub _snv_file_unfiltered {
    my $self = shift;
    my $build_id = $self->build_id;

    #Note:  This switch is used to ensure backwards compatibility with 'old' per chromosome data.  
    #Eventually will be removed.
 
    #The 'new' whole genome way 
    if ( $build_id < 0 || $build_id > 96763806 ) {
        my $unfiltered = $self->snp_related_metric_directory .'/snps_all_sequences';
        unless (-e $unfiltered) {
            die 'No variant snps files were found.';
        }
        return $unfiltered;
    } 
    else {
    #The 'old' per chromosome way
        $self->X_snv_file_unfiltered();
    }

}


sub X_snv_file_unfiltered {
    my $self = shift;
    my $unfiltered = $self->snp_related_metric_directory .'/all.snps';
    unless (-e $unfiltered) {
        # make a combined snp file
        my @old = $self->_variant_list_files();
        if (@old) {
            warn "building $unfiltered\n";
            my $tmp = Genome::Utility::FileSystem->create_temp_file_path("snpfilter");
            Genome::Utility::FileSystem->cat(
                                             input_files => \@old,
                                             output_file => $tmp,
                                         );
            unless (Genome::Model::Tools::Snp::Sort->execute(
                                                             snp_file => $tmp,
                                                             output_file => $unfiltered,
                                                         )) {
                $self->error_message('Failed to execute snp sort command for snv file unfiltered'. $unfiltered);
            }
        }
    }
    return $unfiltered;
}


sub _snv_file_filtered {
    my $self = shift;

    my $filtered;
    my $unfiltered = $self->_snv_file_unfiltered;

    my $build_id = $self->build_id;
 
    #Note:  This switch is to insure backward compatibility while generating reports.  
    #Builds before the id below generated files on a per chromosome basis.
    #Test builds and current production builds generate data on a whole genome basis.

    #'new', whole genome 
    if ( $build_id < 0 || $build_id > 96763806 ) {
        $filtered = $self->filtered_snp_file();
        $self->status_message("********************Path for filtered indelpe file: $filtered");
    } 
    else {
    #'old', per chromosme
       $filtered = $unfiltered; 
       $filtered =~ s/all/filtered.indelpe/g;
    }

    unless (-e $filtered) {
        $self->error_message("Failed to find valid snv_file_filtered: $filtered");
        return;
    }
    
    return $filtered;
}

sub filtered_snp_file {
    my ($self) = @_;
    return join('/', $self->snp_related_metric_directory(), '/filtered.indelpe.snps');
}


sub unfiltered_snp_file {
    return shift->snp_related_metric_directory . '/snps_all_sequences';
}


sub filtered_indel_file {
    my $self = shift;
    
    if ($self->_snp_caller_type eq 'sam') {
        return $self->snp_related_metric_directory . '/indels_all_sequences.filtered';
    }
    elsif ($self->_snp_caller_type eq 'maq') {
        $self->warning_message('Maq tool was used for indel calling. indelpe.sorted.out is filtered sorted indelpe output');
        return $self->snp_related_metric_directory . '/indelpe.sorted.out';
    }
    else {
        $self->error_message('Unknown snp caller: '.$self->_snp_caller_type);
        return;
    }
}


sub unfiltered_indel_file {
    my $self =shift;

    if ($self->_snp_caller_type eq 'sam') {
        return $self->snp_related_metric_directory . '/indels_all_sequences';
    }
    elsif ($self->_snp_caller_type eq 'maq') {
        $self->warning_message('Maq tool was used for indel calling. indels_all_sequences is the output of indelsoa, not indelpe');
        return $self->snp_related_metric_directory . '/indels_all_sequences';
    }
    else {
        $self->error_message('Unknown snp caller: '.$self->_snp_caller_type);
        return;
    }
}

#clearly if multiple aligners/programs becomes common practice, we should be delegating to the appropriate module to construct this directory
sub _variant_list_files {
    return shift->_variant_files('snps', @_);
}

sub _variant_filtered_list_files {
    my ($self, $ref_seq) = @_;
    my $caller_type = $self->_snp_caller_type;
    my $pattern = '%s/'.$caller_type.'_snp_related_metrics/snps_%s.filtered';
    return $self->_files_for_pattern_and_optional_ref_seq_id($pattern, $ref_seq);
}

sub _variant_pileup_files {
    return shift->_variant_files('pileup', @_);
}

sub _variant_detail_files {
    return shift->_variant_files('report_input', @_);
}

sub _variation_metrics_files {
    return shift->_files_for_pattern_and_optional_ref_seq_id('%s/other_snp_related_metrics/variation_metrics_%s.csv',@_);
}

sub _variant_files {
    my ($self, $file_type, $ref_seq) = @_;
    my $caller_type = $self->_snp_caller_type;
    my $pattern = '%s/'.$caller_type.'_snp_related_metrics/'.$file_type.'_%s';
    return $self->_files_for_pattern_and_optional_ref_seq_id($pattern, $ref_seq);
}

sub _transcript_annotation_files {
    return shift->_files_for_pattern_and_optional_ref_seq_id('%s/annotation/%s_snp.transcript',@_);
}

sub other_snp_related_metric_directory {
    my $self = shift;
    return $self->data_directory . "/other_snp_related_metrics/";
}

sub snp_related_metric_directory {
    my $self = shift;
    return $self->data_directory . '/' . $self->_snp_caller_type . '_snp_related_metrics';
}

sub _snp_caller_type {
    return shift->model->_snp_caller_type;
}
    
sub _filtered_variants_dir {
    my $self = shift;
    return sprintf('%s/filtered_variations/',$self->data_directory);
}

sub _reports_dir {
    my $self = shift;
    return sprintf('%s/annotation/',$self->data_directory);
}

sub _files_for_pattern_and_optional_ref_seq_id {
    my ($self, $pattern, $ref_seq) = @_;

    if ((defined $ref_seq and $ref_seq eq 'all_sequences') or !defined $ref_seq) {
        return sprintf($pattern, $self->data_directory, 'all_sequences');
    }

    my @files = 
    map { 
        sprintf(
            $pattern,
            $self->data_directory,
            $_
        )
    }
    grep { $_ ne 'all_sequences' }
    grep { (!defined($ref_seq)) or ($ref_seq eq $_) }
    $self->model->get_subreference_names;

    return @files;
}

sub log_directory {
    my $self = shift;
    return $self->data_directory."/logs/";
}

sub rmdup_metrics_file {
    my $self = shift;
    return $self->log_directory."/mark_duplicates.metrics";
}

sub rmdup_log_file {
    my $self = shift;
    return $self->log_directory."/mark_duplicates.log";
} 


sub whole_map_file {
    my $self = shift;
    return $self->accumulated_alignments_directory .'/whole.map';
}

sub whole_rmdup_map_file {
    my $self = shift;
    return $self->accumulated_alignments_directory .'/whole_rmdup.map';
}

sub whole_rmdup_bam_file {
    my $self = shift;

    my @files = glob($self->accumulated_alignments_directory .'/*_merged_rmdup.bam');

    if (@files > 1) {
        my @not_symlinks;
        my @symlinks;
        for (@files) {
            if (-l $_) {
                push @symlinks, $_;
            }
            else {
                push @not_symlinks, $_;
            }
        }
        if (@not_symlinks == 1) {
            $self->warning_message("Found multiple files, but all but one are symlinks.  Selecting @not_symlinks.  Ignoring @symlinks.");
            return $not_symlinks[0];
        }
        else {
	        $self->error_message("Multiple merged rmdup bam file found.");
            return;
        }
    }
    elsif (@files == 0) {
	    return $self->accumulated_alignments_directory.'/'.$self->build_id.'_merged_rmdup.bam';
    }
    else {
    	return $files[0];
    }
}

sub generate_tcga_file_name {
    my $self = shift;
    my $model = $self->model;
    my $dna_id  = $model->subject_id;

    my $ex_species_name = GSC::DNAExternalName->get( dna_id => $dna_id, name_type => 'biospecimen id',);
    if ( !defined($ex_species_name) ) {
        $self->error_message("The external species name via the name type of 'biospecimen id' is not defined for this model.  Cannot generate a TCGA file name.");
        return;
    }
   
    my $ex_plate_name = GSC::DNAExternalName->get( dna_id => $dna_id, name_type => 'plate id',);
    if ( !defined($ex_plate_name) ) {
        $self->error_message("The external plate name via the name type of 'palate id' is not defined for this model.  Cannot generate a TCGA file name.");
        return;
    }

    return $ex_species_name->name."-".$ex_plate_name->name."-09"; 
}

sub reference_coverage_directory {
    my $self = shift;
    return $self->data_directory .'/reference_coverage';
}

sub layers_file {
    my $self = shift;
    return $self->reference_coverage_directory .'/whole.layers';
}

sub genes_file {
    my $self = shift;

    my $model = $self->model;
    my $reference_build = $model->reference_build;
    return $reference_build->data_directory .'/BACKBONE.tsv';
}

sub relative_coverage_files {
    my $self = shift;
    my $model = $self->model;
    #TODO: Once refcov is a genome tool we should have better control over output file names
    #return glob($self->reference_coverage_directory .'/'. $model->subject_name .'_relative_coverage_*.tsv');
    return grep { $_ !~ /bias_\d+_\w+$/ } glob($self->reference_coverage_directory .'/bias_*');
}

sub relative_coverage_file {
    my $self = shift;
    my $size_fraction = shift;
    unless ($size_fraction) {
        return;
    }
    #TODO: Once refcov is a genome tool we should have better control over output file names
    #return $self->_coverage_data_file('relative_coverage_'. $size_fraction);
    return $self->reference_coverage_directory .'/bias_'. $size_fraction;
}

sub coverage_stats_file {
    my $self = shift;
    return $self->_coverage_data_file('stats');
}

sub coverage_progression_file {
    my $self = shift;
    return $self->_coverage_data_file('progression');
}

sub breakdown_file {
    my $self = shift;
    # TODO: once breakdown.pl is turned into a genome command handling file names should be easier
    return $self->reference_coverage_directory .'/breakdown.tsv';
    # return $self->_coverage_data_file('breakdown');
}

sub coverage_breadth_bin_file {
    my $self = shift;
    return $self->_coverage_data_file('coverage_bins');
}

sub coverage_size_histogram_file {
    my $self = shift;
    return $self->_coverage_data_file('size_histos');
}

sub _coverage_data_file {
    my $self = shift;
    my $type = shift;
    my $model = $self->model;
    return $self->reference_coverage_directory .'/'. $model->subject_name .'_'. $type .'.tsv';
}

sub maplist_file_paths {
    my $self = shift;

    my %p = @_;
    my $ref_seq_id;

    if (%p) {
        $ref_seq_id = $p{ref_seq_id};
    } 
    else {
        $ref_seq_id = 'all_sequences';
    }
    my @map_lists = grep { -e $_ } glob($self->accumulated_alignments_directory .'/*_'. $ref_seq_id .'.maplist');
    unless (@map_lists) {
        $self->error_message("No map lists found for ref seq $ref_seq_id in " . $self->accumulated_alignments_directory);
    }
    return @map_lists;
}

sub duplicates_map_file {
    my $self = shift;
    return $self->accumulated_alignments_directory .'/all_sequences.duplicates.map';
}


sub accumulate_maps {
    my $self=shift;

    my $model = $self->model;
    my $result_file;

    #replace 999999 with the cut off value... 
    #2761337261 is an old AML2 model with newer data
    if ($model->id < 0 || $model->id >= 2766822526 || $model->id == 2761337261) {
        $result_file = $self->resolve_accumulated_alignments_filename;
    } 
    else {
        my @all_map_lists;
        my @chromosomes = $model->reference_build->subreference_names;
        foreach my $c (@chromosomes) {
            my $a_ref_seq = Genome::Model::RefSeq->get(model_id => $model->id, ref_seq_name=>$c);
            my @map_list = $a_ref_seq->combine_maplists;
            push (@all_map_lists, @map_list);
        }

        $result_file = '/tmp/mapmerge_'. $model->genome_model_id;
        $self->warning_message("Performing a complete mapmerge for $result_file \n"); 

        my ($fh,$maplist) = File::Temp::tempfile;
        $fh->print(join("\n",@all_map_lists),"\n");
        $fh->close;

        my $maq_version = $model->read_aligner_version;
        system "gmt maq vmerge --maplist $maplist --pipe $result_file --version $maq_version &";

        $self->status_message("gmt maq vmerge --maplist $maplist --pipe $result_file --version $maq_version &");
        my $start_time = time;
        until (-p "$result_file" or ( (time - $start_time) > 100) )  {
            $self->status_message("Waiting for pipe...");
            sleep(5);
        }
        unless (-p "$result_file") {
            die "Failed to make pipe? $!";
        }
        $self->status_message("Streaming into file $result_file.");
        $self->warning_message("mapmerge complete.  output filename is $result_file");
        chmod 00664, $result_file;
    }
    return $result_file;
}

sub maq_version_for_pp_parameter {
    my $self = shift;
    my $pp_param = shift;

    $pp_param = 'read_aligner_version' unless defined $pp_param;
    my $pp = $self->model->processing_profile;
    unless ($pp->$pp_param) {
        die("Failed to resolve path for maq version using processing profile parameter '$pp_param'");
    }
    my $version = $pp->$pp_param;
    unless ($version) {
        $pp_param =~ s/version/name/;
        $version = $pp->$pp_param;
        $version =~ s/^\D+//;
        $version =~ s/_/\./g;
    }
    unless ($version) {
        die("Failed to resolve a version for maq using processing profile parameter '$pp_param'");
    }
    return $version;
}

sub path_for_maq_version {
    my $self = shift;
    my $pp_param = shift;

    my $version = $self->maq_version_for_pp_parameter($pp_param);
    return Genome::Model::Tools::Maq->path_for_maq_version($version);
}


sub resolve_accumulated_alignments_filename {
    my $self = shift;

    my $aligner_path = $self->path_for_maq_version('read_aligner_version');

    my %p = @_;
    my $ref_seq_id = $p{ref_seq_id};
    my $library_name = $p{library_name};

    my $alignments_dir = $self->accumulated_alignments_directory;

    if ($library_name && $ref_seq_id) {
        return "$alignments_dir/$library_name/$ref_seq_id.map";
    } 
    elsif ($ref_seq_id) {
        return $alignments_dir . "/mixed_library_submaps/$ref_seq_id.map";
    } 
    else {
        my @files = glob("$alignments_dir/mixed_library_submaps/*.map");
        my $tmp_map_file = Genome::Utility::FileSystem->create_temp_file_path('ACCUMULATED_ALIGNMENTS-'. $self->model_id .'.map');
        if (-e $tmp_map_file) {
            unless (unlink $tmp_map_file) {
                $self->error_message('Could not unlink existing temp file '. $tmp_map_file .": $!");
                die($self->error_message);
            }
        }
        require POSIX;
        unless (POSIX::mkfifo($tmp_map_file, 0700)) {
            $self->error_message("Can not create named pipe ". $tmp_map_file .":  $!");
            die($self->error_message);
        }
        my $cmd = "$aligner_path mapmerge $tmp_map_file " . join(" ", @files) . " &";
        my $rv = Genome::Utility::FileSystem->shellcmd(
                                                       cmd => $cmd,
                                                       input_files => \@files,
                                                       output_files => [$tmp_map_file],
                                                   );
        unless ($rv) {
            $self->error_message('Failed to execute mapmerge command '. $cmd);
            die($self->error_message);
        }
        return $tmp_map_file;
    }
}


1;


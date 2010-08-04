package Genome::Model::Build::ReferenceAlignment;

#REVIEW fdu
#Looks ok to me except for two ideas:
#1. can accumulated_alignment be renamed to dedup ?
#2. can eviscerate method be pulled out to base class G::M::Build so other types of builds besides ref-align can use it too ?


use strict;
use warnings;

use Genome;
use File::Path 'rmtree';
use Carp;

class Genome::Model::Build::ReferenceAlignment {
    is => 'Genome::Model::Build',
    is_abstract => 1,
    subclassify_by => 'subclass_name',
    has => [
        subclass_name => { is => 'String', len => 255, is_mutable => 0, column_name => 'SUBCLASS_NAME',
                           calculate_from => ['model_id'],
                           calculate => sub {
                                            my($model_id) = @_;
                                            return unless $model_id;
                                            my $model = Genome::Model->get($model_id);
                                            Carp::croak("Can't find Genome::Model with ID $model_id while resolving subclass for Build") unless $model;
                                            my $seq_platform = $model->sequencing_platform;
                                            Carp::croak("Can't subclass Build: Genome::Model id $model_id has no sequencing_platform") unless $seq_platform;
                                            return return __PACKAGE__ . '::' . Genome::Utility::Text::string_to_camel_case($seq_platform);
                                         },
                          },
        gold_snp_path => {
            # this should be updated to have an underlying merged microarray model, which could update, and result in a new build
            via => 'model',
        }, 
    ],
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
        $self->error_message('No instrument data have been added to model! '. $model->name);
        $self->error_message("The following command will add all available instrument data:\ngenome model instrument-data assign  --model-id=". $model->id .' --all');
        $self->delete;
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
        for my $res ($ida->results) {
            my ($ct, $trim_ct) = $res->calculate_base_counts_after_trimq2;
            return unless $ct and $trim_ct;
            $total_ct += $ct;
            $total_trim_ct += $trim_ct;
        }
    }

    return ($total_ct, $total_trim_ct);
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
    
    my $expected_name = $self->unfiltered_snp_file . '.filtered';
    
    if(Genome::Utility::FileSystem->check_for_path_existence($expected_name)) {
        return $expected_name;
    }
    
    my $old_name = join('/', $self->snp_related_metric_directory(), 'filtered.indelpe.snps');
    if(Genome::Utility::FileSystem->check_for_path_existence($old_name)) {
        return $old_name;
    }
    
    #Hasn't been created yet--if we're on this snapshot it would use this name
    return $expected_name;
}


sub unfiltered_snp_file {
    return shift->snp_related_metric_directory . '/snps_all_sequences';
}

sub filtered_indel_file {
    my $self = shift;

    #Current standard location--if this file exists it's the right one
    my $expected_location = $self->snp_related_metric_directory . '/indels_all_sequences.filtered';

    #Current standard location
    return $expected_location if Genome::Utility::FileSystem->check_for_path_existence($expected_location);
    
    #Old standard varied by detector type
    my $old_location;
    if ($self->_snp_caller_type eq 'sam') {
        $old_location = $self->snp_related_metric_directory . '/indels_all_sequences.filtered';
    }
    elsif ($self->_snp_caller_type eq 'maq') {
        $self->warning_message('Maq tool was used for indel calling. indelpe.sorted.out is filtered sorted indelpe output');
        $old_location = $self->snp_related_metric_directory . '/indelpe.sorted.out';
    }
    elsif ($self->_snp_caller_type eq 'varscan') {
        $old_location = $self->snp_related_metric_directory . '/varscan.status.indel';
    }

    return $old_location if $old_location and Genome::Utility::FileSystem->check_for_path_existence($old_location);
    
    #If we didn't find it anywhere, it might not have been generated yet--which makes it a new build and should use current standard
    return $expected_location;
}

sub unfiltered_indel_file {
    my $self =shift;
    
    my $expected_location = $self->snp_related_metric_directory . '/indels_all_sequences';
    return $expected_location if Genome::Utility::FileSystem->check_for_path_existence($expected_location);
    
    #Old standard varied by detector type
    my $old_location;
    if ($self->_snp_caller_type eq 'sam') {
        $old_location = $self->snp_related_metric_directory . '/indels_all_sequences';
    }
    elsif ($self->_snp_caller_type eq 'maq') {
        $self->warning_message('Maq tool was used for indel calling. indels_all_sequences is the output of indelsoa, not indelpe');
        $old_location = $self->snp_related_metric_directory . '/indels_all_sequences';
    }
    elsif ($self->_snp_caller_type eq 'varscan') {
        $old_location = $self->snp_related_metric_directory . '/varscan.status.indel';
    }

    return $old_location if $old_location and Genome::Utility::FileSystem->check_for_path_existence($old_location);
    
    #If we didn't find it anywhere, it might not have been generated yet--which makes it a new build and should use current standard
    return $expected_location;
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
    
    my $expected_directory = $self->data_directory . '/snp_related_metrics';
    
    return $expected_directory if Genome::Utility::FileSystem->check_for_path_existence($expected_directory);
    
    #if it doesn't exist, try falling back to the "old" way of doing it
    my $old_directory = $self->data_directory . '/' . $self->_snp_caller_type . '_snp_related_metrics';
    
    return $old_directory if Genome::Utility::FileSystem->check_for_path_existence($old_directory);
    
    #if neither exist, then assume we're a new build where it hasn't been created yet
    return $expected_directory;
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

sub mark_duplicates_library_metrics_hash_ref {
    my $self = shift;
    my $subject = $self->model->subject_name;
    my $mark_duplicates_metrics = $self->rmdup_metrics_file;
    my $fh = Genome::Utility::FileSystem->open_file_for_reading($mark_duplicates_metrics);
    unless ($fh) {
        die('Failed to open mark duplicates metrics file '. $mark_duplicates_metrics);
    }
    my %library_metrics;
    my @keys;
    while (my $line = $fh->getline) {
        chomp($line);
        if ($line =~ /^LIBRARY/) {
            @keys = split("\t",$line);
        }
        if ($line =~ /^($subject\S*)/) {
            unless (@keys) {
                die('Failed to find header line starting with LIBRARY!');
            }
            my $library = $1;
            my @values = split("\t",$line);
            for (my $i = 0; $i < scalar(@values); $i++) {
                my $key = $keys[$i];
                my $value = $values[$i];
                $library_metrics{$library}{$key} = $value;

                my $metric_key = join('_', $library, $key);
                $self->set_metric($metric_key, $value);
            }
        }
    }
    $fh->close;
    unless (keys %library_metrics) {
        die('Failed to find a library that matches the subject name '. $subject); 
    }
    return \%library_metrics;
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

    my $expected_whole_rmdup_bam_file = $self->accumulated_alignments_directory.'/'.$self->build_id.'_merged_rmdup.bam';
    if(-e $expected_whole_rmdup_bam_file) {
        #If we found one that matches the current naming convention, use it.
        return $expected_whole_rmdup_bam_file; 
    }

    #Otherwise try to find one under a previous naming convention.
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
         #There hasn't been one generated yet at all--give the name we'd expect to find
            return $expected_whole_rmdup_bam_file;
    }
    else {
        return $files[0];
    }
}


sub whole_rmdup_bam_flagstat_file {
    my $self = shift;

    my $bam_file  = $self->whole_rmdup_bam_file;
    my $flag_file = $bam_file . '.flagstat';

    unless (-s $flag_file) {
        $self->status_message("Create bam flagstat file: $flag_file");
        my $cmd = Genome::Model::Tools::Sam::Flagstat->create(
            bam_file       => $bam_file,
            output_file    => $flag_file,
            include_stderr => 1,
        );

        unless ($cmd and $cmd->execute) {
            $self->error_message('Failed to create or execute flagstat command for '. $bam_file);
            return;
        }
    }

    return $flag_file;
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

####BEGIN CAPTURE SECTION####

####END CAPTURE SECTION####

####BEGIN CDNA SECTION####

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

sub transcript_bed_file {
    my $self = shift;
    my $model = $self->model;
    my $reference_build = $model->reference_build;
    return $reference_build->data_directory .'/transcripts.bed';
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

#####END OF CDNA SECTION###

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

sub start {
    my $self = shift;
    unless (defined($self->model->reference_sequence_build)) {
        my $msg = 'The model you are trying to build does not have reference_sequence_build set.  Please redefine the model or set this value manually.';
        $self->error_message($msg);
        croak $msg;
    }
    return $self->SUPER::start(@_);
}

sub accumulated_alignments_directory {
    my $self = shift;
    return $self->data_directory . '/alignments';
}

sub accumulated_alignments_disk_allocation {
    my $self = shift;

    my $dedup_event = Genome::Model::Event::Build::ReferenceAlignment::DeduplicateLibraries->get(model_id=>$self->model->id,
                                                                                                   build_id=>$self->build_id);

    return if (!$dedup_event);
    
    my $disk_allocation = Genome::Disk::Allocation->get(owner_class_name=>ref($dedup_event), owner_id=>$dedup_event->id);
    
    return $disk_allocation;
}

sub variants_directory {
    my $self = shift;
    return $self->data_directory . '/variants';
}

sub delete {
    my $self = shift;
    
    # if we have an alignments directory, nuke it first since it has its own allocation
    if (-e $self->accumulated_alignments_directory) {
        unless($self->eviscerate()) {
            my $eviscerate_error = $self->error_mesage();
            $self->error_message("Eviscerate failed: $eviscerate_error");
            return;
        };
    }
    
    $self->SUPER::delete(@_);
}

# nuke the accumulated alignment directory
sub eviscerate {
    my $self = shift;
    
    $self->status_message('Entering eviscerate for build:' . $self->id);
    
    my $alignment_alloc = $self->accumulated_alignments_disk_allocation;
    my $alignment_path = ($alignment_alloc ? $alignment_alloc->absolute_path :  $self->accumulated_alignments_directory);
    
    if (!-d $alignment_path && !-l $self->accumulated_alignments_directory) {
        $self->status_message("Nothing to do, alignment path doesn't exist and this build has no alignments symlink.  Skipping out.");
        return;
    }

    $self->status_message("Removing tree $alignment_path");
    if (-d $alignment_path) {
        rmtree($alignment_path);
        if (-d $alignment_path) {
            $self->error_message("alignment path $alignment_path still exists after evisceration attempt, something went wrong.");
            return;
        }
    }
    
    if ($alignment_alloc) {
        unless ($alignment_alloc->deallocate) {
            $self->error_message("could not deallocate the alignment allocation.");
            return;
        }
    }

    if (-l $self->accumulated_alignments_directory && readlink($self->accumulated_alignments_directory) eq $alignment_path ) {
        $self->status_message("Unlinking symlink: " . $self->accumulated_alignments_directory);
        unless(unlink($self->accumulated_alignments_directory)) {
            $self->error_message("could not remove symlink to deallocated accumulated alignments path");
            return;
        }
    }

    return 1;
}

sub _X_resolve_subclass_name { # only temporary, subclass will soon be stored
    my $class = shift;
    return __PACKAGE__->_resolve_subclass_name_by_sequencing_platform(@_);
}


sub _resolve_subclass_name_for_sequencing_platform {
    my ($class,$sequencing_platform) = @_;
    my @type_parts = split(' ',$sequencing_platform);

    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);

    my $class_name = join('::', 'Genome::Model::Build::ReferenceAlignment' , $subclass);
    return $class_name;
}

sub _resolve_sequencing_platform_for_subclass_name {
    my ($class,$subclass_name) = @_;
    my ($ext) = ($subclass_name =~ /Genome::Model::Build::ReferenceAlignment::(.*)/);
    return unless ($ext);
    my @words = $ext =~ /[a-z]+|[A-Z](?:[A-Z]+|[a-z]*)(?=$|[A-Z])/g;
    my $sequencing_platform = lc(join(" ", @words));
    return $sequencing_platform;
}

#This directory is used by both cDNA and now Capture models as well
sub reference_coverage_directory {
    my $self = shift;
    return $self->data_directory .'/reference_coverage';
}

####BEGIN REGION OF INTEREST SECTION####

sub alignment_summary_file {
    my ($self,$wingspan) = @_;
    unless (defined($wingspan)) {
        die('Must provide wingspan_value to method alignment_summary_file in '. __PACKAGE__);
    }
    my @as_files = glob($self->reference_coverage_directory .'/*wingspan_'. $wingspan .'-alignment_summary.tsv');
    unless (@as_files) {
        return;
    }
    unless (scalar(@as_files) == 1) {
        die("Found multiple stats files:\n". join("\n",@as_files));
    }
    return $as_files[0];
}

sub alignment_summary_hash_ref {
    my ($self,$wingspan) = @_;

    unless ($self->{_alignment_summary_hash_ref}) {
        my $wingspan_array_ref = $self->wingspan_values_array_ref;
        my %alignment_summary;
        for my $wingspan( @{$wingspan_array_ref}) {
            my $as_file = $self->alignment_summary_file($wingspan);
            my $reader = Genome::Utility::IO::SeparatedValueReader->create(
                separator => "\t",
                input => $as_file,
            );
            unless ($reader) {
                $self->error_message('Can not create SeparatedValueReader for input file '. $as_file);
                return;
            }
            my $data = $reader->next;
            $reader->input->close;
            
            # Calculate percentages
            
            # percent aligned
            $data->{percent_aligned} = sprintf("%.02f",(($data->{total_aligned_bp} / $data->{total_bp}) * 100));
            
            # duplication rate
            $data->{percent_duplicates} = sprintf("%.03f",(($data->{total_duplicate_bp} / $data->{total_aligned_bp}) * 100));
            
            # on-target alignment
            $data->{percent_target_aligned} = sprintf("%.02f",(($data->{total_target_aligned_bp} / $data->{total_aligned_bp}) * 100));
            
            # on-target duplicates
            $data->{percent_target_duplicates} = sprintf("%.02f",(($data->{duplicate_target_aligned_bp} / $data->{total_target_aligned_bp}) * 100));
            
            # off-target alignment
            $data->{percent_off_target_aligned} = sprintf("%.02f",(($data->{total_off_target_aligned_bp} / $data->{total_aligned_bp}) * 100));
            
            # off-target duplicates
            $data->{percent_off_target_duplicates} = sprintf("%.02f",(($data->{duplicate_off_target_aligned_bp} / $data->{total_off_target_aligned_bp}) * 100));
            
            for my $key (keys %$data) {
                my $metric_key = join('_', 'wingspan', $wingspan, $key);
                $self->set_metric($metric_key, $data->{$key});
            }
            
            $alignment_summary{$wingspan} = $data;
        }
        $self->{_alignment_summary_hash_ref} = \%alignment_summary;
    }
    return $self->{_alignment_summary_hash_ref};
}

sub coverage_stats_directory_path {
    my ($self,$wingspan) = @_;
    return $self->reference_coverage_directory .'/wingspan_'. $wingspan;
}

sub stats_file {
    my $self = shift;
    my $wingspan = shift;
    unless (defined($wingspan)) {
        die('Must provide wingspan_value to method coverage_stats_file in '. __PACKAGE__);
    }
    my $coverage_stats_directory = $self->coverage_stats_directory_path($wingspan);
    my @stats_files = glob($coverage_stats_directory.'/*STATS.tsv');
    unless (@stats_files) {
        return;
    }
    unless (scalar(@stats_files) == 1) {
        die("Found multiple stats files:\n". join("\n",@stats_files));
    }
    return $stats_files[0];
}


sub coverage_stats_hash_ref {
    my $self = shift;
    unless ($self->{_coverage_stats_hash_ref}) {
        my @headers = qw/name pc_covered length covered_bp uncovered_bp mean_depth stdev_mean_depth median_depth gaps mean_gap_length stdev_gap_length median_gap_length minimum_depth minimum_depth_discarded_bp pc_minimum_depth_discarded_bp/;

        my %stats;
        my $min_depth_array_ref = $self->minimum_depths_array_ref;
        my $wingspan_array_ref = $self->wingspan_values_array_ref;
        for my $wingspan (@{$wingspan_array_ref}) {
            my $stats_file = $self->stats_file($wingspan);
            my $reader = Genome::Utility::IO::SeparatedValueReader->create(
                separator => "\t",
                input => $stats_file,
                #TODO: Add headers to the stats file
                headers => \@headers,
            );
            unless ($reader) {
                $self->error_message('Can not create SeparatedValueReader for file '. $stats_file);
                die $self->error_message;
            }
            while (my $data = $reader->next) {
                push @{$stats{$wingspan}{$data->{name}}}, $data;
            }
            $reader->input->close;
        }
        $self->{_coverage_stats_hash_ref} = \%stats;
    }
    return $self->{_coverage_stats_hash_ref};
}

sub coverage_stats_summary_file {
    my ($self,$wingspan) = @_;
    unless (defined($wingspan)) {
        die('Must provide wingspan_value to method coverage_stats_file in '. __PACKAGE__);
    }
    my @stats_files = glob($self->coverage_stats_directory_path($wingspan) .'/*STATS.txt');
    unless (@stats_files) {
        return;
    }
    unless (scalar(@stats_files) == 1) {
        die("Found multiple stats summary files:\n". join("\n",@stats_files));
    }
    return $stats_files[0];
}

sub coverage_stats_summary_hash_ref {
    my $self = shift;
    unless ($self->{_coverage_stats_summary_hash_ref}) {
        my %stats_summary;
        my $min_depth_array_ref = $self->minimum_depths_array_ref;
        my $wingspan_array_ref = $self->wingspan_values_array_ref;
        for my $wingspan (@{$wingspan_array_ref}) {
            my $stats_summary = $self->coverage_stats_summary_file($wingspan);
            my $reader = Genome::Utility::IO::SeparatedValueReader->create(
                separator => "\t",
                input => $stats_summary,
            );
            unless ($reader) {
                $self->error_message('Can not create SeparatedValueReader for file '. $stats_summary);
                die $self->error_message;
            }
            while (my $data = $reader->next) {
                $stats_summary{$wingspan}{$data->{minimum_depth}} = $data;
                
                # record stats as build metrics
                for my $key (keys %$data) {
                    my $metric_key = join('_', 'wingspan', $wingspan, $data->{'minimum_depth'}, $key);
                    $self->set_metric($metric_key, $data->{$key});
                }
            }
            $reader->input->close;
        }
        $self->{_coverage_stats_summary_hash_ref} = \%stats_summary;
    }
    return $self->{_coverage_stats_summary_hash_ref};
}

sub region_of_interest_set_bed_file {
    my $self = shift;

    my $roi_set = $self->model->region_of_interest_set;
    return unless $roi_set;

    my $bed_file_path = $self->reference_coverage_directory .'/'. $roi_set->id .'.bed';
    unless (-e $bed_file_path) {
        unless ($roi_set->print_bed_file($bed_file_path)) {
            die('Failed to print bed file to path '. $bed_file_path);
        }
    }
    return $bed_file_path;
}

sub _resolve_coverage_stats_params {
    my $self = shift;
    my $pp = $self->processing_profile;
    my $coverage_stats_params = $pp->coverage_stats_params;
    my ($minimum_depths,$wingspan_values,$base_quality_filter,$mapping_quality_filter) = split(':',$coverage_stats_params);
    if (defined($minimum_depths) && defined($wingspan_values)) {
        $self->{_minimum_depths} = $minimum_depths;
        $self->{_wingspan_values} = $wingspan_values;
        if (defined($base_quality_filter) && ($base_quality_filter ne '')) {
            $self->{_minimum_base_quality} = $base_quality_filter;
        }
        if (defined($mapping_quality_filter) && ($mapping_quality_filter ne '')) {
            $self->{_minimum_mapping_quality} = $mapping_quality_filter;
        }
    } else {
        die('minimum_depth and wingspan_values are required values.  Failed to parse coverage_stats_params: '. $coverage_stats_params);
    }
    return 1;
}

sub minimum_depths {
    my $self = shift;
    unless ($self->{_minimum_depths}) {
        $self->_resolve_coverage_stats_params;
    }
    return $self->{_minimum_depths};
}

sub minimum_depths_array_ref {
    my $self = shift;
    my $minimum_depths = $self->minimum_depths;
    return unless $minimum_depths;
    my @min_depths = split(',',$minimum_depths);
    return \@min_depths;
}

sub wingspan_values {
    my $self = shift;
    unless ($self->{_wingspan_values}) {
        $self->_resolve_coverage_stats_params;
    }
    return $self->{_wingspan_values};
}

sub wingspan_values_array_ref {
    my $self = shift;
    my $wingspan_values = $self->wingspan_values;
    return unless defined($wingspan_values);
    my @wingspans = split(',',$wingspan_values);
    return \@wingspans;
}

sub minimum_base_quality {
    my $self = shift;
    unless ($self->{_minimum_base_quality}) {
        $self->_resolve_coverage_stats_params;
    }
    return $self->{_minimum_base_quality};
}

sub minimum_mapping_quality {
    my $self = shift;
    unless ($self->{_minimum_mapping_quality}) {
        $self->_resolve_coverage_stats_params;
    }
    return $self->{_minimum_mapping_quality};
}

####END REGION OF INTEREST SECTION####

1;


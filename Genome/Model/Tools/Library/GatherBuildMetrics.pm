package Genome::Model::Tools::Library::GatherBuildMetrics;

use strict;
use warnings;

use Genome;
use Command;
use IO::File;

class Genome::Model::Tools::Library::GatherBuildMetrics {
    is => 'Command',
    has => [
    build_id => { 
        type => 'String',
        is_optional => 0,
        doc => "build id of the build to gather metrics for",
    },
    ]
};


sub execute {
    my $self=shift;
    $DB::single = 1;
    my $build_id = $self->build_id;

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
    printf STDERR "Grabbing information for model %s (build %s)\n", $model->name, $build->build_id;       
    #Grab all alignment events so we can filter out ones that are still running or are abandoned
    # get all align events for the current running build
    my @align_events = Genome::Model::Event->get(event_type => 
        {operator => 'like', value => '%align-reads%'},
        build_id => $build,
        model_id => $model->id,
    );
    printf STDERR "%d lanes in build\n", scalar(@align_events);
    #now just get the Succeeded events to pass along for further processing
    # THIS MAY NOT INCLUDE ANY EVENTS
    my @events = Genome::Model::Event->get(event_type => 
        {operator => 'like', value => '%align-reads%'},
        build_id => $build,
        event_status => 'Succeeded',
        model_id => $model->id,

    );
    # if it does not include any succeeded events - die
    unless (@events) {
        $self->error_message(" No alignments have Succeeded on the build ");
        return;
    }
    printf STDERR "Using %d lanes to calculate metrics\n", scalar(@events);
    #Convert events to InstrumentDataAssignment objects
    my @idas = map { $_->instrument_data_assignment } @events;

    my %stats_for;
    my %readset_stats;

    #print STDOUT join "\t",("Name","#Reads_Mapped","#Reads_Total","isPaired","#Reads_Mapped_asPaired","Median_Insert_Size","Standard_Deviation_Above_Insert_Size",),"\n";
#Completely undeprecated loop over the readsets
    foreach my $ida (@idas) {
        my $library = $ida->library_name;
        unless(defined($library)) {
            $self->error_message("No library defined for ".$ida->instrument_data_id);
            next;
        }
        my $lane_name = $ida->short_name."_".$ida->subset_name;
        my $alignment = $ida->alignment;
        my @aligner_output = $alignment->aligner_output_file_paths;
        if(@aligner_output > 1) {
            $self->error_message("More than one aligner_output_file! WTF!");
        }
        my $hash = $alignment->get_alignment_statistics($aligner_output[0]);
        $stats_for{$library}{total_read_sets} += 1;
        unless(defined($hash)) {
            #ignore runs where there are no aligner outputs (shouldn't really happen anymore)
            $stats_for{$library}{no_aligner_stats} += 1;
            next;
        }
        my $read1 = GSC::RunLaneSolexa->get($ida->instrument_data->fwd_seq_id);
        my $read2 = GSC::RunLaneSolexa->get($ida->instrument_data->rev_seq_id);
        if($read2 && $read2->run_type eq 'Paired End Read 1') {
            #assume the other is read2
            ($read1, $read2) = ($read2, $read1);
        }
        my ($error1, $error2) = ($read1 ? $read1->filt_error_rate_avg : '-', $read2 ? $read2->filt_error_rate_avg : '-');
        $error1 ||= '-';
        $error2 ||= '-';
        $stats_for{$library}{$hash->{isPE}}{mapped} += $hash->{mapped};
        $stats_for{$library}{$hash->{isPE}}{total} += $hash->{total};
        $stats_for{$library}{$hash->{isPE}}{paired} += $hash->{paired};
        $stats_for{$library}{$hash->{isPE}}{read_sets} += 1;
        my $median_insert_size = $ida->median_insert_size;
        my $sd_above_insert_size = $ida->sd_above_insert_size;
        if(defined($median_insert_size) && $hash->{isPE}) {
            $stats_for{$library}{median_insert_size} += $median_insert_size;
            $stats_for{$library}{median_insert_size_n} +=1;
        }
        if(defined($sd_above_insert_size) && $hash->{isPE}) {
            $stats_for{$library}{sd_above_insert_size} += $sd_above_insert_size;
            $stats_for{$library}{sd_above_insert_size_n} += 1;
        }

        #clean things up for printing
        unless(defined($median_insert_size)) {
            $median_insert_size = '-';
        }
        unless(defined($sd_above_insert_size)) {
            $sd_above_insert_size = '-';
        }
        my $gerald_clusters = $ida->instrument_data->clusters;
        my $read_length = $ida->instrument_data->read_length;
        $stats_for{$library}{$hash->{isPE}}{total_clusters} += $gerald_clusters;
        $stats_for{$library}{$hash->{isPE}}{total_gbp} += $gerald_clusters * ($read_length-1) / 1000000000;
        $readset_stats{$lane_name} = join "\t",($lane_name,$library, $hash->{mapped},$hash->{total},$hash->{isPE}, $hash->{paired},$median_insert_size,$sd_above_insert_size,$gerald_clusters, $read_length, $error1, $error2, sprintf("%0.02f",$hash->{mapped}/$hash->{total}),),"\n";
    }
    print("Flowcell_Lane\tLibrary\t#Reads_Mapped\t#Reads_Total\tMapped_as_PE\t#Mapped_as_Pairs\tMedian_Insert_Size\tSD_Above_Insert_Size\tFiltered_Clusters\tCycles(Read_Length+1)\tRead1_Avg_Error_Rate\tRead2_Avg_Error_Rate\tMapping_Rate\n"); 
    foreach my $lane (sort keys %readset_stats) {
        print $readset_stats{$lane};
    }
    my $total_lanes = 0;
    my $total_reads = 0;
    my $total_mapped_reads = 0;
    my $total_paired_reads = 0;
    my $total_clusters = 0;
    my $total_gbp = 0;

    print STDOUT "\n\n",'-' x 5,'Library Averages','-' x 5,"\n";
    foreach my $library (keys %stats_for) {
        print "$library: ",$stats_for{$library}{total_read_sets}, " Total Lanes\n";
        $total_lanes += $stats_for{$library}{total_read_sets};
        if(exists($stats_for{$library}{1})) {
            $total_reads += $stats_for{$library}{1}{total};
            $total_mapped_reads += $stats_for{$library}{1}{mapped};
            $total_paired_reads += $stats_for{$library}{1}{paired};
            $total_clusters += $stats_for{$library}{1}{total_clusters};
            $total_gbp += $stats_for{$library}{1}{total_gbp};

            print "\tPaired Lanes: ", $stats_for{$library}{1}{read_sets},"\n";
            print "\t\tFiltered Clusters: ", $stats_for{$library}{1}{total_clusters}, "\n";
            print "\t\tGbp: ", $stats_for{$library}{1}{total_gbp}, "\n";
            print "\t\tTotal Reads: ", $stats_for{$library}{1}{total}, "\n";
            print "\t\tMapped Reads: ", $stats_for{$library}{1}{mapped}, "\n";
            printf "\t\tMapping Rate: %0.02f%%\n", $stats_for{$library}{1}{mapped}/$stats_for{$library}{1}{total} * 100;
            print "\t\tPaired Reads: ", $stats_for{$library}{1}{paired}, "\n";
            printf "\t\tPaired Rate: %0.02f%%\n", $stats_for{$library}{1}{paired}/$stats_for{$library}{1}{mapped} * 100; 
            print "\t\tThere were ", $stats_for{$library}{median_insert_size_n}, " out of ", $stats_for{$library}{1}{read_sets}, " lanes where the median insert size was available\n";
            printf "\t\tFrom these the average median insert size was %0.2f\n\n",$stats_for{$library}{median_insert_size}/$stats_for{$library}{median_insert_size_n};


            print "\t\tThere were ", $stats_for{$library}{sd_above_insert_size_n}, " out of ", $stats_for{$library}{1}{read_sets}, " lanes where the sd above the insert size was available\n";
            printf "\t\tFrom these the average sd above the insert size was %0.2f\n\n",$stats_for{$library}{sd_above_insert_size}/$stats_for{$library}{sd_above_insert_size_n};
        }
        if(exists($stats_for{$library}{0})) {

            $total_reads += $stats_for{$library}{0}{total};
            $total_mapped_reads += $stats_for{$library}{0}{mapped};
            print "\tFragment Lanes: ", $stats_for{$library}{0}{read_sets},"\n";
            print "\t\tFiltered Clusters: ", $stats_for{$library}{0}{total_clusters}, "\n";
            print "\t\tGbp: ", $stats_for{$library}{0}{total_gbp}, "\n";
            print "\t\tTotal Reads: ", $stats_for{$library}{0}{total}, "\n";
            print "\t\tMapped Reads: ", $stats_for{$library}{0}{mapped}, "\n";
            printf "\t\tMapping Rate: %0.02f%%\n", $stats_for{$library}{0}{mapped}/$stats_for{$library}{0}{total} * 100;
        }
    }

    #print model totals, this probably shouldn't go in this module but it can sit here for now
    print STDOUT "\n\n",'-' x 5,'Model Averages','-' x 5,"\n";
    print "\tTotal Lanes: ", $total_lanes, "\n";
    printf "\tTotal Runs: %0.02f\n", $total_lanes / 8; 
    print "\tTotal Clusters: ", $total_clusters,"\n";
    print "\tTotal Gbp: ", $total_gbp,"\n";
    print "\tTotal Reads: ", $total_reads, "\n";
    print "\tMapped Reads: ", $total_mapped_reads, "\n";
    printf "\tMapping Rate: %0.02f%%\n", $total_mapped_reads/$total_reads * 100;
    print "\tPaired Reads: ", $total_paired_reads, "\n";

    return 1;

}


1;

sub help_brief {
    "Prints out various paired end library metrics regarding mapping and paired end-ness"
}

sub help_detail {
    <<'HELP';
This script uses the Genome Model API to grab out all alignment events for a model and grab net metrics for the entire library. It ignores runs which have not succeeded in their alignment (silently). 
HELP
}

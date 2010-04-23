#:boberkfe it would be nice if the other reports stored summary data as build metrics so that this
#:boberkfe could generate without having to parse out the individual files in the report paths.

package Genome::Model::ReferenceAlignment::Report::Summary;

use strict;
use warnings;

use Genome;

use App::Report;
use CGI;
use IO::String;
use Template;
use Data::Dumper;
use POSIX;

my $base_template_path = __PACKAGE__->_base_path_for_templates;

class Genome::Model::ReferenceAlignment::Report::Summary {
    is => 'Genome::Model::Report',
    has => [
        report_templates => {
            is => 'String',
            is_many => 1,
            default_value => [
                 "$base_template_path.html.tt2",
                 "$base_template_path.txt.tt2"
            ],
            doc => 'The paths of template(s) to use to format the report.  (In .tt2 format)',
        },
        name => {
            default_value => 'Summary',
        },
        description => {
            default_value => "Link to summary report will go here",
        },
    ],
};

# TODO: move up into base class
sub _base_path_for_templates
{
    my $module = __PACKAGE__;
    $module =~ s/::/\//g;
    $module .= '.pm';
    my $module_path = $INC{$module};
    unless ($module_path) {
        die "Module " . __PACKAGE__ . " failed to find its own path!  Checked for $module in \%INC...";
    }
    return $module_path;
}

sub _add_to_report_xml
{
    my $self = shift;
    my $template = shift;

    my @templates = $self->report_templates;
    unless (@templates) {
        die "No report templates assigned!  Cannot generate any content."
    }

    #my $data = { description => $self->generate_report_brief };
    my $data = {};

    for my $template (@templates) {
        my $content = $self->generate_report_detail($template);
        my ($format,$key);
        if ($content =~ /\<\s*HTML/i) {
            $format = 'HTML';
            $key = 'html';
        }
        else {
            $format = 'text';
            $key = 'txt';
        }
        if (exists $data->{$key}) {
            die "Multiple templates return content in $format format.  This is not supported, sadly."
                . "  Error processing $template";
        }
        $data->{$key} = $content;
    };
    return $data;
}

sub generate_report_brief
{
    my $self=shift;
    return "Link to summary report will go here";
}

sub generate_report_detail
{
    my $self = shift;
    my $template = shift;
    unless ($template) {
        die "please specify which template to use for this report!";
    }

    my $model = $self->model;
    my $build = $self->build;

    $self->status_message("Running report summary for build ".$build->id.".");
    my $body = IO::String->new();
    die $! unless $body;
    my $summary = $self->get_summary_information($template);
    $body->print($summary);
    $body->seek(0, 0);
    return join('', $body->getlines);
}

sub get_summary_information
{
    my $self = shift;
    my $template = shift;
    unless ($template) {
        die "please specify which template to use for this report!";
    }

    my $build = $self->build;
    my $model = $build->model;

    my $content;

    #################################
    my $na = "Not Available";

    my $haploid_coverage=$na;

    my $total_unfiltered_snps=$na;
    my $total_filtered_snps=$na;

    my $unfiltered_dbsnp_positions=$na;
    my $filtered_dbsnp_positions=$na;

    my $unfiltered_dbsnp_concordance=$na;
    my $filtered_dbsnp_concordance=$na;

    my $report_dir = $build->resolve_reports_directory;

    my $mapcheck_report_file = $report_dir."/Mapcheck/report.html";
    my $goldsnp_report_file = $report_dir."/Gold_SNP_Concordance/report.html";
    my $dbsnp_report_file = $report_dir."/dbSNP_Concordance/report.txt";
    my $input_base_count_report_file = $report_dir . "/Input_Base_Count/report.html";

    ##match mapcheck report
    my $fh = new IO::File($mapcheck_report_file, "r");
    if ($fh) {
        my $mapcheck_contents = get_contents($fh);
        if ( ($mapcheck_contents =~ m/Average depth across all non-gap regions: (\S+)/g ) || ($mapcheck_contents =~ m/\nAverage Coverage:(\S+)/g ) ) {
            $haploid_coverage=$1 if defined($1);
            if ($haploid_coverage) {
                $build->set_metric( 'haploid_coverage', $haploid_coverage );
            }
        }
        $fh->close();
    } else {
        $self->status_message("Could not locate RefSeqMaq report at $mapcheck_report_file!");
    }

    ##match goldsnp report
    $fh = new IO::File($goldsnp_report_file, "r");

    my $unfiltered_diploid_het_coverage_actual_number = $na;
    my $unfiltered_diploid_het_coverage_percent = $na;
    my $unfiltered_diploid_hom_coverage_actual_number = $na;
    my $unfiltered_diploid_hom_coverage_percent = $na;

    my $filtered_diploid_het_coverage_actual_number = $na;
    my $filtered_diploid_het_coverage_percent = $na;
    my $filtered_diploid_hom_coverage_actual_number = $na;
    my $filtered_diploid_hom_coverage_percent = $na;

    if ($fh) {
        my $goldsnp_contents = get_contents($fh);
        my ($unfiltered,$filtered) = ($goldsnp_contents =~ /Gold Concordance for Unfiltered SNVs(.*)Gold Concordance for SNPFilter SNVs(.*)/ms);

        my ($unfiltered_het, $unfiltered_hom) = ($unfiltered    =~ /(heterozygous calls.*)Partially.*?(homozygous calls.*)Partially/ms);
        my ($filtered_het,   $filtered_hom)   = ($filtered      =~ /(heterozygous calls.*)Partially.*?(homozygous calls.*)Partially/ms);


        if ($unfiltered_het =~ m|heterozygous - 1 allele variant</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td></tr>|) {
            #print ("Found match. >$1, $2<\n");
            $unfiltered_diploid_het_coverage_actual_number=$1;
            $unfiltered_diploid_het_coverage_percent=$2;
        }

        if ($filtered_het =~ m|heterozygous - 1 allele variant</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td></tr>|) {
            #print ("Found match. >$1, $2, $3<\n");
            $filtered_diploid_het_coverage_actual_number=$1;
            $filtered_diploid_het_coverage_percent=$2;
        }

        if ($unfiltered_hom =~ m|homozygous variant</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td></tr>|) {
            #print ("Found match. >$1, $2, $3<\n");
            $unfiltered_diploid_hom_coverage_actual_number=$1;
            $unfiltered_diploid_hom_coverage_percent=$2;
        }

        if ($filtered_hom =~ m|homozygous variant</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td></tr>|) {
            #print ("Found match. >$1, $2, $3<\n");
            $filtered_diploid_hom_coverage_actual_number=$1;
            $filtered_diploid_hom_coverage_percent=$2;
        }
        $fh->close;
    }

    ##match dbsnp report
    $fh = new IO::File($dbsnp_report_file, "r");
    if ($fh) {
        my $dbsnp_contents = get_contents($fh);
        # get unfiltered data
        if ( $dbsnp_contents =~ /^\s*total unfiltered SNPs: (\S+)$/m) {
            $total_unfiltered_snps = $1;
        } else {
            $self->status_message("Could not extract total unfiltered SNPs from $dbsnp_report_file!");
        }

        if ( $dbsnp_contents =~ /^\s*unfiltered dbSNP positions: (\S+)$/m) {
            $unfiltered_dbsnp_positions = $1;
        } else {
            $self->status_message("Could not extract unfiltered dbSNP positions from $dbsnp_report_file!");
        }

        if ( $dbsnp_contents =~ /^\s*unfiltered concordance: (\S+)$/m) {
            $unfiltered_dbsnp_concordance = $1;
        } else {
            $self->status_message("Could not extract unfiltered concordance from $dbsnp_report_file!");
        }

        # get filtered data
        if ( $dbsnp_contents =~ /^\s*total filtered SNPs: (\S+)$/m) {
            $total_filtered_snps = $1;
            $self->status_message("total_filtered_snps: $total_filtered_snps");
        } else {
            $self->status_message("Could not extract total filtered SNPs from $dbsnp_report_file!");
        }

        if ( $dbsnp_contents =~ /^\s*filtered dbSNP positions: (\S+)$/m) {
            $filtered_dbsnp_positions = $1;
            $self->status_message("filtered_dbsnp_positions: $filtered_dbsnp_positions");
        } else {
            $self->status_message("Could not extract filtered dbSNP positions from $dbsnp_report_file!");
        }

        if ( $dbsnp_contents =~ /^\s*filtered concordance: (\S+)$/m) {
            $filtered_dbsnp_concordance = $1;
            $self->status_message("filtered_dbsnp_concordance: $filtered_dbsnp_concordance");
        } else {
            $self->status_message("Could not extract filtered concordance from $dbsnp_report_file!");
        }

        # if ( $dbsnp_contents =~ m|There were (\S+) positions in dbSNP for a concordance of (\S+)%|g ) {
        #     $unfiltered_dbsnp_concordance=$2;
        # }
        # if ( $dbsnp_contents =~ m|There were (\S+) positions in dbSNP for a concordance of (\S+)%|g ) {
        #     $filtered_dbsnp_concordance=$2;
        # }
        $fh->close();
    }

    ##the number of instrument data assignments is:
    my @inst_data_ass = $build->instrument_data_assignments;

    my @inst_data;
    eval { @inst_data = $build->instrument_data };
    @inst_data = Genome::InstrumentData->get(id => [ map { $_->instrument_data_id } @inst_data_ass ]);

    my $total_bases = 0;
    for (@inst_data_ass) {
        my $inst_data = Genome::InstrumentData->get($_->instrument_data_id);

        if ($inst_data->can('total_bases_read'))  {
            $total_bases += $inst_data->total_bases_read($_->filter_desc);
        }
    }
    my $total_gigabases = sprintf("%.03f", $total_bases/1000000000);

    if ($model->read_trimmer_name =~ /^trimq2/) {
        my ($total_ct, $total_trim_ct) = $build->calculate_input_base_counts_after_trimq2;
        if ($total_ct and $total_trim_ct) {
            my $gb       = sprintf("%.03f", $total_ct/1000000000);
            my $trim_gb  = sprintf("%.03f", $total_trim_ct/1000000000);
            $total_gigabases = "$trim_gb/$gb";
        }
        else {
            $self->warning_message("Failed to get input base counts after trimq2");
        }
    }

    # summarize the instrument data
    my %library_lane_counts;

    unless ($model->read_aligner_name =~ /Imported$/i) {
        my %library_lanes;
        for my $i (@inst_data) {
            my $library_name = $i->library_name;
            my $a = $library_lanes{$library_name} ||= [];
            push @$a, $i->run_name . "/" . $i->subset_name
        }
        for my $library_name (keys %library_lanes) {
            $library_lane_counts{$library_name} = scalar(@{ $library_lanes{$library_name} })
        }
    }

    # sample variables
    my $sample;
    if($model->subject_type eq 'sample_name' or $model->subject_type eq 'genomic_dna') {
        $sample = $model->subject;
    } elsif ($model->subject_type eq 'library_name') {
        my $library = $model->subject;
        if($library) {
            $sample = $library->sample;
        }
    }

    my ($extraction_label,$tissue_label,$extraction_name,$extraction_id,$extraction_desc,$extraction_type) = ($na,$na,$na,$na,$na,$na);
    if ($sample) {
        $tissue_label = $sample->tissue_label || $na;

        $extraction_label = $sample->extraction_label || $na;
        $extraction_name  = $sample->name || $na;
        $extraction_id    = $sample->id || $na;
        #$extraction_desc  = $sample->description;
        $extraction_type  = $sample->sample_type || $na;
    }
    else {
        $self->warning_message("No sample found for " . $model->subject_name);
    }

    # patient variables
    my $source;
    my ($source_upn,$source_desc) = ($na,$na);
    $source = $sample->source if $sample;
    if ($source) {
        $source_upn = $source->name || $na;
        $source_desc = $source->description || $na;
        #$source_gender = $source->gender;
    }
    else {
        $self->warning_message("No source individual/population found for sample!");
    }

    my $taxon;
    my $taxon_id;
    my $species = $na;
    my $species_latin_name = $na;
    $taxon = $sample->taxon;

    if ($taxon) {
        $taxon_id = $taxon->taxon_id;
        $species = $taxon->species_name;
        $species_latin_name = $taxon->species_latin_name;
    } else {
        $self->warning_message("No taxon found for sample!");
    }

    my $ref_seq_name = $self->model->reference_build->name;
    my $ref_seq_dir = $self->model->reference_build->data_directory;

    $DB::single = 1;

    # processing profile
    my $pp = $model->processing_profile;

    my @unfiltered_files = $build->_snv_file_unfiltered;
    my $unfiltered_snp_calls = `wc -l @unfiltered_files | tail -n 1`;
    $unfiltered_snp_calls =~ s/\s\S+\s*$//i;
    $unfiltered_snp_calls =~ s/\s//g;

    my @filtered_files = $build->_snv_file_filtered;
    my $filtered_snp_calls = `wc -l @filtered_files | tail -n 1`;
    $filtered_snp_calls =~ s/\s\S+\s*$//i;
    $filtered_snp_calls =~ s/\s//g;

    my $snp_chromosomes = $self->model->reference_build->description;
    my $snp_caller = $self->model->genotyper_name;

    my @stat = stat($filtered_files[-1]);
    my $time = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime($stat[10]));

    my $model_name = $model->name;
    my $build_id = $build->id;
    my $data_directory = $build->data_directory . "/";

    my @vars = (
        model_id                                      => $model->id,
        model_name                                    => $model->name,

        patient_upn                                   => $source_upn,

        taxon_id                                      => $taxon_id,
        species                                       => $species,
        species_latin_name                            => $species_latin_name,

        ref_seq_name                                  => $ref_seq_name,
        ref_seq_dir                                   => $ref_seq_dir,

        tissue_sample_label                           => $tissue_label,

        extraction_label                              => $extraction_label,
        extraction_type                               => $extraction_type,
        extraction_name                               => $extraction_name,
        extraction_id                                 => $extraction_id,
        extraction_desc                               => $extraction_desc,

        processing_profile_type                       => $pp->type_name,
        processing_profile_name                       => $pp->name,
        processing_profile_id                         => $pp->id,

        build_id                                      => $build->id,
        build_date                                    => $time,
        data_directory                                => $data_directory,

        total_number_of_lanes                         => scalar(@inst_data_ass),
        total_gigabases                               => $total_gigabases,
        libraries                                     => [ sort keys %library_lane_counts ],
        lanes_by_library                              => \%library_lane_counts,

        haploid_coverage                              => $haploid_coverage,

        unfiltered_snp_calls                          => commify($unfiltered_snp_calls),
        filtered_snp_calls                            => commify($filtered_snp_calls),

        snp_chromosomes                               => $snp_chromosomes,
        snp_caller                                    => $snp_caller . " SNPfilter",

        total_filtered_snps                           => commify($total_filtered_snps),
        total_unfiltered_snps                         => commify($total_unfiltered_snps),

        unfiltered_dnsbp_positions                    => commify($unfiltered_dbsnp_positions),
        filtered_dnsbp_positions                      => commify($filtered_dbsnp_positions),

        unfiltered_dbsnp_concordance                  => $unfiltered_dbsnp_concordance,
        filtered_dbsnp_concordance                    => $filtered_dbsnp_concordance,

        unfiltered_diploid_het_coverage_actual_number => commify($unfiltered_diploid_het_coverage_actual_number),
        unfiltered_diploid_het_coverage_percent       => $unfiltered_diploid_het_coverage_percent,
        unfiltered_diploid_hom_coverage_actual_number => commify($unfiltered_diploid_hom_coverage_actual_number),
        unfiltered_diploid_hom_coverage_percent       => $unfiltered_diploid_hom_coverage_percent,

        filtered_diploid_het_coverage_actual_number   => commify($filtered_diploid_het_coverage_actual_number),
        filtered_diploid_het_coverage_percent         => $filtered_diploid_het_coverage_percent,
        filtered_diploid_hom_coverage_actual_number   => commify($filtered_diploid_hom_coverage_actual_number),
        filtered_diploid_hom_coverage_percent         => $filtered_diploid_hom_coverage_percent,
    );

    #$self->status_message("Summary Report values: ".Dumper(\@vars) );

    ##################################

    my $tt = Template->new({
         ABSOLUTE => 1,
        #INCLUDE_PATH => '/gscuser/jpeck/svn/pm2/Genome/Model/ReferenceAlignment/Report',
        #INTERPOLATE  => 1,
    }) || die "$Template::ERROR\n";

    my $varstest = {
        name     => 'Mickey',
        debt     => '3 riffs and a solo',
        deadline => 'the next chorus',
    };

    $self->status_message("processing template $template");

    my $rv = $tt->process($template, { @vars }, \$content) || die $tt->error(), "\n";
    if ($rv != 1) {
   	    die "Bad return value from template processing for summary report generation: $rv ";
    }
    unless ($content) {
        die "No content returned from template processing!";
    }

    return $content;
}

sub get_contents {
   my $in = shift;
   my $ret = "";
   while (<$in>) {
      $ret.= $_;
   }
   return $ret;
}

sub commify {
	local $_  = shift;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}

1;

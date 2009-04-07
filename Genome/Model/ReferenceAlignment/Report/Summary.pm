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
                 "$base_template_path.txt.tt2",
            ],
            doc => 'The paths of template(s) to use to format the report.  (In .tt2 format)',
        },
        name => {
            default_value => 'Summary',
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

sub _generate_data 
{
    my $self = shift;
    my $template = shift;

    my @templates = $self->report_templates;
    unless (@templates) {
        die "No report templates assigned!  Cannot generate any content."
    }

    my $data = { description => $self->generate_report_brief };
    
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

$DB::single = 1;   

    my $build = $self->build;
    my $model = $build->model;
    
    my $content;
 
    ################################# 
    my $na = "Not Available";
    
    my $haploid_coverage=$na;
    
    my $unfiltered_dbsnp_concordance=$na;
    my $filtered_dbsnp_concordance=$na;

    my $report_dir = $build->resolve_reports_directory;

    my $mapcheck_report_file = $report_dir."/RefSeqMaq/report.html";
    my $goldsnp_report_file = $report_dir."/Gold_SNP_Concordance/report.html";
    my $dbsnp_report_file = $report_dir."/dbSNP_Concordance/report.html";

    ##match mapcheck report
    my $fh = new IO::File($mapcheck_report_file, "r");
    if ($fh) {
        my $mapcheck_contents = get_contents($fh);
        if ($mapcheck_contents =~ m/Average depth across all non-gap regions: (\S+)/g ) {
            $haploid_coverage=$1 if defined($1);
        }
        $fh->close();
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
        
        my ($unfiltered_het, $unfiltered_hom) = ($unfiltered    =~ /(There were \d+ heterozygous calls.*).*?(There were \d+ homozygous calls.*)/ms);
        my ($filtered_het,   $filtered_hom)   = ($filtered      =~ /(There were \d+ heterozygous calls.*).*?(There were \d+ homozygous calls.*)/ms);

	if ($unfiltered_het =~ m|>Matching Gold Genotype</span>
</div>
<div>
<span style=\"padding-left:10px;\"></span><span style=\"padding-left:10px;\">heterozygous - 1 allele variant</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span>|g) {
            #print ("Found match. >$1, $2<\n");
            $unfiltered_diploid_het_coverage_actual_number=$1; 
            $unfiltered_diploid_het_coverage_percent=$2; 
        }
        
        if ($filtered_het =~ m|heterozygous - 1 allele variant</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span>|g) {
            #print ("Found match. >$1, $2, $3<\n");
            $filtered_diploid_het_coverage_actual_number=$1; 
            $filtered_diploid_het_coverage_percent=$2; 
        }
        
        if ($unfiltered_hom =~ m|homozygous variant</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span>|g) {
            #print ("Found match. >$1, $2, $3<\n");
            $unfiltered_diploid_hom_coverage_actual_number=$1; 
            $unfiltered_diploid_hom_coverage_percent=$2; 
        }
        
        if ($filtered_hom =~ m|homozygous variant</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span><span style=\"padding-left:10px;\">(\S+)</span>|g) {
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
        if ( $dbsnp_contents =~ m|There were (\S+) positions in dbSNP for a concordance of (\S+)%|g ) {
            $unfiltered_dbsnp_concordance=$2;
        } 
        if ( $dbsnp_contents =~ m|There were (\S+) positions in dbSNP for a concordance of (\S+)%|g ) {
            $filtered_dbsnp_concordance=$2;
        }
        $fh->close();
    }

    ##the number of instrument data assignments is:
    my @inst_data_ass = $build->instrument_data_assignments;
    
    my @inst_data;
    eval { @inst_data = $build->instrument_data };
    @inst_data = Genome::InstrumentData->get(id => [ map { $_->instrument_data_id } @inst_data_ass ]);
    
    # summarize the instrument data
    my %library_lanes;
    for my $i (@inst_data) {
        my $library_name = $i->library_name;
        my $a = $library_lanes{$library_name} ||= [];
        push @$a, $i->run_name . "/" . $i->subset_name
    }
    my %library_lane_counts;
    for my $library_name (keys %library_lanes) {
        $library_lane_counts{$library_name} = scalar(@{ $library_lanes{$library_name} })
    }

    # sample variables
    my $sample = $model->subject;
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

    # processing profile
    my $pp = $model->processing_profile;

    my @unfiltered_files = $build->_variant_list_files;
    my $unfiltered_snp_calls = `wc -l @unfiltered_files | tail -n 1`;
    $unfiltered_snp_calls =~ s/total//i;
    $unfiltered_snp_calls =~ s/\s//g;
    
    my @filtered_files = $build->_variant_filtered_list_files;
    my $filtered_snp_calls = `wc -l @filtered_files | tail -n 1`;
    $filtered_snp_calls =~ s/total//i;
    $filtered_snp_calls =~ s/\s//g;

    my @stat = stat($filtered_files[-1]); 
    my $time = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime($stat[10]));

    # gscweb can't see sata disk? TODO: fixme
    #my $data_directory = $build->data_directory;
    my $model_name = $model->name;
    my $build_id = $build->id;
    my $data_directory = "/gscmnt/839/info/medseq/model_links/$model_name/build$build_id/";

    my @vars = (
        model_id                => $model->id,
        model_name              => $model->name,
        
        patient_upn             => $source_upn,
        
        tissue_sample_label     => $tissue_label,
        
        extraction_label        => $extraction_label,
        extraction_type         => $extraction_type,
        extraction_name         => $extraction_name,
        extraction_id           => $extraction_id,
        extraction_desc         => $extraction_desc,
        
        processing_profile_type => $pp->type_name,
        processing_profile_name => $pp->name,
        processing_profile_id   => $pp->id,
        
        build_id                => $build->id,
        build_date              => $time,
        data_directory          => $data_directory,
        
        total_number_of_lanes   => scalar(@inst_data_ass),
        libraries               => [ sort keys %library_lane_counts ],
        lanes_by_library        => \%library_lane_counts,
        
        haploid_coverage        => $haploid_coverage,
        
        unfiltered_snp_calls                            => commify($unfiltered_snp_calls),
        filtered_snp_calls                              => commify($filtered_snp_calls),
        
        unfiltered_dbsnp_concordance                    => $unfiltered_dbsnp_concordance,
        filtered_dbsnp_concordance                      => $filtered_dbsnp_concordance,
        
        unfiltered_diploid_het_coverage_actual_number   => commify($unfiltered_diploid_het_coverage_actual_number),
        unfiltered_diploid_het_coverage_percent         => $unfiltered_diploid_het_coverage_percent,
        unfiltered_diploid_hom_coverage_actual_number   => commify($unfiltered_diploid_hom_coverage_actual_number),
        unfiltered_diploid_hom_coverage_percent         => $unfiltered_diploid_hom_coverage_percent,
        
        filtered_diploid_het_coverage_actual_number     => commify($filtered_diploid_het_coverage_actual_number),
        filtered_diploid_het_coverage_percent           => $filtered_diploid_het_coverage_percent,
        filtered_diploid_hom_coverage_actual_number     => commify($filtered_diploid_hom_coverage_actual_number),
        filtered_diploid_hom_coverage_percent           => $filtered_diploid_hom_coverage_percent,
    );

    $self->status_message("Summary Report values: ".Dumper(\@vars) );
    
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

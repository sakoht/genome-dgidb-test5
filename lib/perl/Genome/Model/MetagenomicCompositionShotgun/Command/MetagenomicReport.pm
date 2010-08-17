package Genome::Model::MetagenomicCompositionShotgun::Command::MetagenomicReport;

use strict;
use warnings;
use Genome;
use Genome::Model::InstrumentDataAssignment;
use File::Path;
use File::Find;

$|=1;

class Genome::Model::MetagenomicCompositionShotgun::Command::MetagenomicReport{
    is => 'Genome::Command::OO',
    doc => 'Generate metagenomic reports for a MetagenomicCompositionShotgun build.',
    has => [
        build_id => {
            is => 'Int',
        },
        taxonomy_file => {
            is => 'Parh',
            is_optional=>1,
        },
        viral_taxonomy_file => {
            is => 'Path',
            is_optional=>1,
        },
        viral_headers_file => {
            is => 'Path',
            is_optional => 1,
        },
        regions_file => {
            is => 'Path',
            is_optional => 1,
        },
        overwrite => {
            is => 'Boolean',
            is_optional => 1,
            default => 0,
        },
        report_dir => {
            is => 'Text',
            is_optional => 1,
        },
    ],
};


sub execute {
    my ($self) = @_;

    my $build = Genome::Model::Build->get($self->build_id);
    my $model = $build->model;

    unless ($self->report_dir){
        $self->report_dir($build->data_directory . "/reports");
    }
    $self->status_message("Report path: " . $self->report_dir);

    my ($metagenomic_ref_build) = grep { $_->model_name=~/part 1 of/ } $model->metagenomic_references;
    unless ($metagenomic_ref_build){
        $self->error_message("couldn't get build for metagenomic reference part 1 model");
        die $self->error_message;
    }
    my $metagenomic_ref_hmp_dir = $metagenomic_ref_build->data_directory."/hmp";
    unless (-d $metagenomic_ref_hmp_dir){
        $self->error_message("Couldn't find hmp dir in latest build of metagenomic reference part 1: $metagenomic_ref_hmp_dir");
        die $self->error_message;
    }
    #TODO these names are bad and should be improved as this pipeline becomes more generic, don't know if taxonomy files will always be available when this is done again.
    
    unless ($self->viral_headers_file){
        $self->viral_headers_file("$metagenomic_ref_hmp_dir/viruses_nuc.fasta.headers");
        unless (-s $self->viral_headers_file){
            $self->error_message("viral headers file doesn't exist or have size: ".$self->viral_headers_file);
        }
    }
    unless ($self->regions_file){
        $self->regions_file("$metagenomic_ref_hmp_dir/combined_refcov_regions_file.regions.txt");
        unless (-s $self->regions_file){
            $self->error_message("refcov regions bed file doesn't exist or have size: ".$self->regions_file);
        }
    }
    unless ($self->taxonomy_file){
        $self->taxonomy_file("$metagenomic_ref_hmp_dir/Bact_Arch_Euky.taxonomy.txt");
        unless (-s $self->taxonomy_file){
            $self->error_message("taxonomy file doesn't exist or have size: ".$self->taxonomy_file);
        }
    }
    unless ($self->viral_taxonomy_file){
        $self->viral_taxonomy_file("$metagenomic_ref_hmp_dir/viruses_taxonomy_feb_25_2010.txt");
        unless (-s $self->viral_taxonomy_file){
            $self->error_message("viral_taxonomy file doesn't exist or have size: ".$self->viral_taxonomy_file);
        }
    }

    my $dir = $build->data_directory;
    my ($meta1_bam, $meta1_flagstat, $meta2_bam, $meta2_flagstat) = map{ $dir ."/$_"}(
        "metagenomic_alignment1.bam",
        "metagenomic_alignment1.bam.flagstat",
        "metagenomic_alignment2.bam",
        "metagenomic_alignment2.bam.flagstat",
    );


    my $merged_bam = $self->report_dir."/metagenomic_alignment.combined.bam";
    if (-e $merged_bam and -e $merged_bam.".OK"){
        $self->status_message("metagenomic merged bam already produced, skipping");
    }else{
        my $rv;

        $self->status_message("starting sort and merge");

        eval{
            $rv = Genome::Model::Tools::Sam::SortAndMergeSplitReferenceAlignments->execute(
                input_files => [$meta1_bam, $meta2_bam],
                output_file => $merged_bam,
            );
        };
        if ($@ or !$rv){
            $self->error_message("Failed to sort and merge metagenomic bams: $@");
            die;
        }

        unless (-s $merged_bam){
            $self->error_message("Merged bam has no size!");
            die;
        }

        system ("touch $merged_bam.OK");
    }

    $self->status_message("Finished sort and merge, compiling metagenomic reports");


    $self->status_message("Starting taxonomy count...\n");
    $DB::single = 1;

    # Load Taxonomy From Taxonomy Files
    my $taxonomy;
    my %taxon_map = (
        species => '1',
        phyla   => '2',
        genus   => '3',
        order   => '4',
        hmp     => '5',
    );
    $taxonomy = $self->_load_taxonomy($self->taxonomy_file, 'Species', \%taxon_map);
    unless(%$taxonomy) {
        $self->error_message("No taxonomy data loaded from " . $self->taxonomy_file . "!");
        die $self->error_message;
    }

    my $viral_taxonomy;
    my %viral_taxon_map = (
        species    => '1',
        genus      => '2',
        subfamily  => '3',
        family     => '4',
        infraorder => '5',
        suborder   => '6',
        superorder => '7',
    );
    $viral_taxonomy = $self->_load_taxonomy($self->viral_taxonomy_file, 'gi', \%viral_taxon_map);
    unless(%$viral_taxonomy) {
        $self->error_message("No viral taxonomy data loaded from " . $self->viral_taxonomy_file . "!");
        die $self->error_message;
    }

    # Count Reference Hits
    my %ref_counts_hash;
    my $ignore_unmapped;
    my $ignore_singleton;
    my $fh = IO::File->new("samtools view $merged_bam |");
    while (<$fh>){
        my @fields = split(/\t/, $_);
        my $bitflag = $fields[1];
        if ($bitflag & 0x0004){
            $ignore_unmapped++;
            next;
        }
        if ($bitflag & 0x0001){
            $ignore_singleton++;
            next;
        }
        my ($ref_name, $null, $gi) = split(/\|/, $fields[2]);
        if ($ref_name eq "VIRL"){
            $ref_name .= "_$gi";
        }
        $ref_counts_hash{$ref_name}++;
    }

    $self->status_message("skipping $ignore_unmapped reads without a metagenomic mapping");
    $self->status_message("skipping $ignore_singleton fragment reads(mate mapped to human)");

    # Count And Record Taxonomy Hits
    my $read_count_output_file = $self->report_dir . '/read_count_output';
    unlink $read_count_output_file if -e $read_count_output_file;
    my $read_cnt_o = Genome::Utility::FileSystem->open_file_for_writing($read_count_output_file);

    my %species_counts_hash;
    my %phyla_counts_hash;
    my %genus_counts_hash;
    my %viral_family_counts_hash;
    my %viral_subfamily_counts_hash;
    my %viral_genus_counts_hash;
    my %viral_species_counts_hash;


    $self->status_message('creating metagenomic count files');

    print $read_cnt_o "Reference Name\t#Reads with hits\tSpecies\tPhyla\tHMP genome\n";
    do {
        use warnings FATAL => 'all';
        for my $ref_id (sort keys %ref_counts_hash){
            if (($ref_id =~ /^BACT/) or ($ref_id =~ /^ARCH/) or ($ref_id =~ /^EUKY/)){
                my $species= $taxonomy->{$ref_id}->{species} || '';
                $species_counts_hash{$species}+=$ref_counts_hash{$ref_id};
                my $phyla=$taxonomy->{$ref_id}->{phyla} || '';
                $phyla_counts_hash{$phyla}+=$ref_counts_hash{$ref_id};
                my $genus=$taxonomy->{$ref_id}->{genus} || '';
                $genus_counts_hash{$genus}+=$ref_counts_hash{$ref_id};
                my $hmp_flag=$taxonomy->{$ref_id}->{hmp}|| '';	
                print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t$species\t$phyla\t$hmp_flag\n";
            }elsif ($ref_id =~ /^VIRL/){ #produce reports for viral taxonomy if available
                my ($gi) = $ref_id =~/^VIRL_(\d+)$/;
                if ($viral_taxonomy->{$gi}){
                    my $species = $viral_taxonomy->{$gi}->{species} || '';
                    $viral_species_counts_hash{$species}+=$ref_counts_hash{$ref_id};
                    my $genus = $viral_taxonomy->{$gi}->{genus} || '';
                    $viral_genus_counts_hash{$genus}+=$ref_counts_hash{$ref_id};
                    my $family = $viral_taxonomy->{$gi}->{family} || '';
                    $viral_family_counts_hash{$family}+=$ref_counts_hash{$ref_id};
                    my $subfamily = $viral_taxonomy->{$gi}->{subfamily} || '';
                    $viral_subfamily_counts_hash{$subfamily}+=$ref_counts_hash{$ref_id};
                    print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t$species\t\t\n";
                }else{
                    print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t\t\t\n";
                }
            }else{
                print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t\t\t\n";
            }
        }
    };
    $read_cnt_o->close;

    my $species_output_file = $self->report_dir . '/species_count';
    my $phyla_output_file = $self->report_dir . '/phyla_count';
    my $genus_output_file = $self->report_dir . '/genus_count';
    my $viral_family_output_file = $self->report_dir . '/viral_family_count';
    my $viral_subfamily_output_file = $self->report_dir . '/viral_subfamily_count';
    my $viral_genus_output_file = $self->report_dir . '/viral_genus_count';
    my $viral_species_output_file = $self->report_dir . '/viral_species_count';
    $self->_write_count_and_close($species_output_file, "Species", \%species_counts_hash);
    $self->_write_count_and_close($phyla_output_file, "Phyla", \%phyla_counts_hash);
    $self->_write_count_and_close($genus_output_file, "Genus", \%genus_counts_hash);
    $self->_write_count_and_close($viral_species_output_file, "Viral Species", \%viral_species_counts_hash);
    $self->_write_count_and_close($viral_genus_output_file, "Viral Genus", \%viral_genus_counts_hash);
    $self->_write_count_and_close($viral_family_output_file, "Viral Family", \%viral_family_counts_hash);
    $self->_write_count_and_close($viral_subfamily_output_file, "Viral Subfamily", \%viral_subfamily_counts_hash);

    
    $self->status_message("classification summary reports and reference hit report finished");

    $self->status_message("running refcov on combined metagenomic alignment bam");

    my $refcov = Genome::Model::Tools::MetagenomicCompositionShotgun::RefCovTool->create(
        working_directory => $self->report_dir,
        aligned_bam_file => $merged_bam,
        regions_file => $self->regions_file,
    );

    $self->status_message("Executing RefCov command ". $refcov->command_name);
    my $rv;
    eval{$rv=$refcov->execute};
    if($@ or !$rv){
        $self->error_message("failed to execute refcov: $@");
        die $self->error_message;
    }
    my $refcov_output = $refcov->report_file;
    unless (-s $refcov_output){
        $self->error_message("refcov output doesn't exist or has zero size: $refcov_output");
    }
    $self->status_message("refcov completed successfully, stats file: $refcov_output");

    $self->status_message("Combining refcov results with taxonomy reports for final summary file");
    ###############################################################################################

    my $refcov_fh           =IO::File->new($refcov_output);
    my $taxonomy_fh         =IO::File->new($self->taxonomy_file);
    my $viral_taxonomy_fh   =IO::File->new($self->viral_headers_file);
    my $read_counts_fh      =IO::File->new($read_count_output_file);
    my $summary_report_fh   =IO::File->new("> ".$self->report_dir."metagenomic_refcov_summary.txt");

    my $data;
    my %print_hash;
    my %header_hash;
    my $ref_data;

    while (my $line = $read_counts_fh->getline) {
        chomp $line;
        next if ($line =~ /^Reference/);
        my @array=split(/\t/,$line);
        my $ref = $array[0];
        $ref = 'VIRL' if $ref =~/VIRL/;
        if ($ref eq 'VIRL'){
            $ref_data->{$ref}->{reads}+=$array[1];
        }else{
            $ref_data->{$ref}->{reads}=$array[1];
            $ref_data->{$ref}->{species}=$array[2];
            $ref_data->{$ref}->{phyla}=$array[3];
            $ref_data->{$ref}->{hmp}=$array[4];
        }
    }
    $read_counts_fh->close;

    while (my $line = $taxonomy_fh->getline)
    {
        chomp $line;
        my ($ref, $species) = split(/\t/,$line);
        my ($gi) = split(/\|/, $ref);
        ($gi) = $gi =~ /([^>]+)/;
        $header_hash{$gi}=$species;
    }
    $taxonomy_fh->close;

    while (my $line = $viral_taxonomy_fh->getline)
    {
        chomp $line;
        my ($gi, @species) = split(/\s+/,$line);
        my $species = "@species";
        $gi = "VIRL_$gi";
        $header_hash{$gi}=$species;
    }
    $viral_taxonomy_fh->close;

    while(my $line = $refcov_fh->getline)
    {
        chomp $line;
        my (@array)=split(/\t/,$line);
        my ($ref)  =split(/\|/, $array[0]);

        my $species = $header_hash{$ref};

        #Assuming that average coverage is calculated over the whole reference instead of just the covered reference. 
        my $cov=$array[2]*$array[5];#2 is total ref bases 5 is avg coverage

        #Refcov fields
        $data->{$ref}->{cov}+=$cov;
        $data->{$ref}->{tot_bp}+=$array[2];	    	
        $data->{$ref}->{cov_bp}+=$array[3];
        $data->{$ref}->{missing_bp}+=$array[4];
    }
    $refcov_fh->close;

    print $summary_report_fh "Reference Name\tPhyla\tHMP flag\tAvg coverage\tPercent Covered\tTotal reference bases\tBases not covered\t#Reads\n";
    #foreach my $s (keys%{$data}){
    for my $s (sort {$a cmp $b} keys%{$data}){
        my $desc=$header_hash{$s};
        $desc ||= $s;
        next if $desc =~/^gi$/;
        my $phy;
        my $hmp;
        my $reads;
        if ( $ref_data->{$s}->{reads}){
            $phy=$ref_data->{$s}->{phyla};
            $hmp=$ref_data->{$s}->{hmp};
            $reads=$ref_data->{$s}->{reads};
        }
        $phy ||= '-';
        $hmp ||= 'N';
        $reads ||= 0;

        my $new_avg_cov=$data->{$s}->{cov}/$data->{$s}->{tot_bp};
        my $new_avg_breadth=$data->{$s}->{cov_bp}*100/$data->{$s}->{tot_bp};
        my $total_bp = $data->{$s}->{tot_bp};
        my $missing_bp = $data->{$s}->{missing_bp};
        print $summary_report_fh "$desc\t$phy\t$hmp\t$new_avg_cov\t$new_avg_breadth\t$total_bp\t$missing_bp\t$reads\n";
    }

    ###############################################################################################

    $self->status_message("metagenomic report successfully completed");

    system("touch ".$self->report_dir."/FINISHED");
    
    return 1;
}

sub _load_taxonomy {
    my ($self, $filename, $header_ignore_str, $taxon_map_ref) = @_;
    my $fh = Genome::Utility::FileSystem->open_file_for_reading($filename);
    my $taxonomy = {};
    my $header = <$fh>;
    unless ($header =~ /^$header_ignore_str/) {
        die "unexpected header $header!  expected =~ $header_ignore_str";
    }
    while (<$fh>) {
        chomp;
        if (/^$header_ignore_str/) {
            die "duplicated header?!?!: $_\n";
        }
        my @fields = split(/\t/, $_);
        for (@fields) {
            s/^\s+//; 
            s/\s+$//;
        }
        # todo: this is a one-line hash slice -ss
        my $ref_id = $fields[0]; 
        for my $taxon (keys %$taxon_map_ref) {
            $taxonomy->{$ref_id}{$taxon} = $fields[$taxon_map_ref->{$taxon}];
        }
    }
    return $taxonomy;
}

sub _write_count_and_close {
    my($self, $filename, $title, $counts_ref) = @_;
    unlink $filename if -e $filename;
    my $file_o=Genome::Utility::FileSystem->open_file_for_writing($filename);
    print $file_o "$title Name\t#Reads with hits\n";
    for my $name (keys %$counts_ref){
        next if (($name eq "") or ($name =~ /^\s+$/));
        print $file_o "$name\t$counts_ref->{$name}\n";
    }
    $file_o->close;
}



1;

package Genome::Model::Tools::MetagenomicCompositionShotgun::CombineAlignments;

use warnings;

use Genome;
use Workflow;
use IO::File;

#gmt hmp-shotgun combine-alignments --sam-input-file=/gscuser/jpeck/sandbox/bams/filter/all_sorted.sam --taxonomy-file=/gscmnt/sata409/research/mmitreva/databases/Bact_Arch.taxonomy.txt --working-directory=/gscuser/jpeck/sandbox/bams/filter/run/ --genus-output-file=/gscuser/jpeck/sandbox/bams/filter/run/genus.txt --phyla-output-file=/gscuser/jpeck/sandbox/bams/filter/run/phyla.txt --read-count-output-file=/gscuser/jpeck/sandbox/bams/filter/run/read-count.txt --sam-combined-output-file=/gscuser/jpeck/sandbox/bams/filter/run/combined.sam 

class Genome::Model::Tools::MetagenomicCompositionShotgun::CombineAlignments {
    is  => ['Command'],
    has => [
        working_directory => {
            is => 'String',
            is_input => '1',
            doc => 'The working directory where results will be deposited.',
        },
        sam_input_file => {
            is => 'String',
            is_input => '1',
            doc => '',
        },
        sam_header_file => {
            is => 'String',
            is_input => '1',
            doc => '',
        },
        taxonomy_file => {
            is => 'String',
            is_input => '1',
            doc => '',
        },
        viral_taxonomy_file => {
            is => 'String',
            is_input => 1,
            doc => '',
            is_optional => 1,
        },
        sam_combined_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        bam_combined_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        read_count_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        phyla_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        genus_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        viral_family_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        viral_subfamily_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        viral_genus_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        viral_species_output_file => {
            is => 'String',
            is_input => '1',
            is_output => '1',
            is_optional =>1,
            doc => '',
        },
        lsf_resource => {
                is_param => 1,
                value => "-R 'select[mem>4000 && model!=Opteron250 && type==LINUX64] span[hosts=1] rusage[mem=4000]' -M 4000000",
                #default_value => "-R 'select[mem>30000 && model!=Opteron250 && type==LINUX64] span[hosts=1] rusage[mem=30000]' -M 30000000",
        },
        _first_of_batch => {
            is => 'String',
            is_optional =>1,
            is_transient =>1,
        },
        _continue_processing => {
            is => 'Integer',
            is_optional =>1,
            is_transient =>1,
            default=>1,
        },
    ],
};


sub help_brief {
    'Combining bam files';
}

sub help_detail {
    return <<EOS
    Combining bam files from different refseqs.
EOS
}

sub get_next_batch {  
    my $self = shift;
    my $fh = shift;

    my $done = 0; 
    my @result;
    undef(@result);
    my $first_of_batch = $self->_first_of_batch;

    push(@result, $first_of_batch);
    my @batch_fields=split(/\t/,$first_of_batch);
    my $batch_name = $batch_fields[0]; 

    my $current_record = $fh->getline; 
    my $current_read_name;
    if ( defined($current_record) ) {  
        my @fields=split(/\t/,$current_record);
        $current_read_name = $fields[0]; 
    } else {
        $done = 1;
    }
 
    while ( ($current_read_name eq $batch_name) && !$done ) {
        push(@result, $current_record); 
        $current_record = $fh->getline;
        if (defined($current_record) ) {
            my @fields=split(/\t/,$current_record);
            $current_read_name =  $fields[0];
        } else {
            $done = 1;
        }
    }

    if ($done) {
        $self->_continue_processing(0);
    } else {
        $self->_first_of_batch($current_record);
    } 

    chomp(@result);
    return @result;

}


sub execute {
    my $self = shift;
    $self->dump_status_messages(1);
    $self->dump_error_messages(1);
    $self->dump_warning_messages(1);

    my $now = UR::Time->now;
    $self->status_message(">>>Starting CombineAlignments execute() at $now"); 
  
  
    my $working_directory= $self->working_directory."/alignments_filtered/";
    my $report_directory= $self->working_directory."/reports/";
    unless (-e $report_directory) {
    	Genome::Utility::FileSystem->create_directory($report_directory);
    }

    $self->read_count_output_file("$report_directory/reads_per_contig.txt") if (!defined($self->read_count_output_file));
    $self->genus_output_file("$report_directory/genus.txt") if (!defined($self->genus_output_file));
    $self->phyla_output_file("$report_directory/phyla.txt") if (!defined($self->phyla_output_file));
    $self->viral_species_output_file("$report_directory/viral_species.txt") if (!defined($self->viral_species_output_file));
    $self->viral_genus_output_file("$report_directory/viral_genus.txt") if (!defined($self->viral_genus_output_file));
    $self->viral_family_output_file("$report_directory/viral_family.txt") if (!defined($self->viral_family_output_file));
    $self->viral_subfamily_output_file("$report_directory/viral_subfamily.txt") if (!defined($self->viral_subfamily_output_file));
    
    $self->sam_combined_output_file("$working_directory/combined.sam") if (!defined($self->sam_combined_output_file));
    my $bam_combined_output_file = "$working_directory/combined.bam";
    my $warn_file = $self->sam_combined_output_file.".warn";

    my @expected_output_files = ($warn_file,$self->read_count_output_file,$self->genus_output_file,$self->phyla_output_file,$bam_combined_output_file);
    if ($self->viral_taxonomy_file){
        push @expected_output_files, ($self->viral_family_output_file, $self->viral_subfamily_output_file, $self->viral_genus_output_file, $self->viral_species_output_file);
    }
    
    my $rv_check = Genome::Utility::FileSystem->are_files_ok(input_files=>\@expected_output_files);
    if ($rv_check) {
        $self->bam_combined_output_file($bam_combined_output_file);
    	$self->status_message("Expected output files exist.  Skipping processing.");
    	$self->status_message("<<<Completed CombineAlignments at ".UR::Time->now);
    	return 1;
    }

    my $sam_i=Genome::Utility::FileSystem->open_file_for_reading($self->sam_input_file);
    my $tax=Genome::Utility::FileSystem->open_file_for_reading($self->taxonomy_file);
    my $v_tax;
    if ($self->viral_taxonomy_file){
        $v_tax = Genome::Utility::FileSystem->open_file_for_reading($self->viral_taxonomy_file);
    }
    my $sam_header_i = Genome::Utility::FileSystem->open_file_for_reading($self->sam_header_file);

    if ( !defined($sam_i) || !defined($tax) || ($self->viral_taxonomy_file and !defined($v_tax)) ) {
        $self->error_message("Failed to open a required file for reading.");
        return;
    }

    #Output files
    my $sam_o=Genome::Utility::FileSystem->open_file_for_writing($self->sam_combined_output_file);
    my $sam_warn=Genome::Utility::FileSystem->open_file_for_writing($warn_file);
    my $read_cnt_o=Genome::Utility::FileSystem->open_file_for_writing($self->read_count_output_file);
    my $phyla_o=Genome::Utility::FileSystem->open_file_for_writing($self->phyla_output_file);
    my $genus_o=Genome::Utility::FileSystem->open_file_for_writing($self->genus_output_file);

    my ($viral_family_o, $viral_subfamily_o, $viral_genus_o, $viral_species_o);
    if ($self->viral_taxonomy_file){
        $viral_family_o=Genome::Utility::FileSystem->open_file_for_writing($self->viral_family_output_file);
        $viral_subfamily_o=Genome::Utility::FileSystem->open_file_for_writing($self->viral_subfamily_output_file);
        $viral_genus_o=Genome::Utility::FileSystem->open_file_for_writing($self->viral_genus_output_file);
        $viral_species_o=Genome::Utility::FileSystem->open_file_for_writing($self->viral_species_output_file);
    }


    if ( !defined($sam_o) || !defined($read_cnt_o) || !defined($phyla_o) || !defined($genus_o) ) {
        $self->error_message("Failed to open an output file for writing.");
        return;
    } 

    #Read taxonomy
    my $taxonomy;
    while(<$tax>){
        chomp;
        my $line=$_;
        next if ($line =~ /^Species/);
        my @array=split(/\t/,$line);
        my $ref=(split(/\|/,$array[0]))[0];
        $ref =~ s/\>//;
        $array[2] =~ s/\s+//g;
        $array[4] =~ s/\s+//g;
        $taxonomy->{$ref}->{species}=$array[1];
        $taxonomy->{$ref}->{phyla}=$array[2];
        $taxonomy->{$ref}->{genus}=$array[3];
        $taxonomy->{$ref}->{hmp}=$array[5];
    }

    my $viral_taxonomy;
    if ($v_tax){
        while(<$v_tax>){
            chomp;
            my $line=$_;
            next if ($line =~ /^gi/);
            my ($gi, $species, $genus,$subfamily, $family, $infraorder, $suborder, $superorder) = split(/\t/,$line);
            $viral_taxonomy->{$gi}->{species} = $species;
            $viral_taxonomy->{$gi}->{genus} = $genus;
            $viral_taxonomy->{$gi}->{subfamily} = $subfamily;
            $viral_taxonomy->{$gi}->{family} = $family;
            $viral_taxonomy->{$gi}->{infraorder} = $infraorder;
            $viral_taxonomy->{$gi}->{suborder} = $suborder;
            $viral_taxonomy->{$gi}->{superorder} = $superorder;
        }

    }

    my $first = 1;
    srand(12345);
    my $selected;
    my $last_read_name = "";
    my %ref_counts_hash; 

    my $done = 0;

    while (my $header_line = $sam_header_i->getline){
        $sam_o->print($header_line);
    }

    my $line = $sam_i->getline;
    $self->_first_of_batch($line); 
    while ($self->_continue_processing) {
        my $data;
        my %lists;
        my @batch = $self->get_next_batch($sam_i);

        foreach my $current_record (@batch) {
            my @fields=split(/\t/,$current_record);
            my $current_read_name =  $fields[0];

            my $bitflag = $fields[1];
            my ($ref, $null, $gi)= split(/\|/,$fields[2]);

            my $rg;
            if ($current_record =~ /RG\:Z\:(\d+)\s/){
                $rg = $1; 
            } 

            my $flag=0;
            unless (($bitflag & 0x0004) or ($bitflag & 0x0008)){
                $flag=1;
                #flag = 1 both ends of the pair hit the same reference;
                #flag = 0 if either the query or mate is unmapped
            } 
            my $mismatches=0;
            if ($current_record =~ /NM\:i\:(\d+)\s/){
                $mismatches=$1;
            }


            $data->{$rg}->{reads}=$current_read_name;
            $data->{$rg}->{ref}=$flag;
            $data->{$rg}->{mismatches}+=$mismatches; 

            $data->{$rg}->{ref_names} ||= {};
            if ($ref eq "VIRL"){
                $data->{$rg}->{ref_names}->{$gi}++;
            }else{
                $data->{$rg}->{ref_names}->{$ref}++;
            }

            
            $lists{$rg} ||= []; 
            push(@{$lists{$rg}}, $current_record);
        } 
        
        for my $rg (keys %$data){
            $data->{$rg}->{unique_references} = scalar (keys %{$data->{$rg}->{ref_names}});
        }

        my @selection = sort { $data->{$b}->{ref} <=> $data->{$a}->{ref} 
                or $data->{$a}->{unique_references} <=> $data->{$b}->{unique_references}
                or $data->{$a}->{mismatches} <=> $data->{$b}->{mismatches} } keys %$data;

        my $selected_rg = shift @selection;
        my @selected_list = @{$lists{$selected_rg}};

        foreach my $selected_record (@selected_list)  {
            print $sam_o $selected_record."\n";
            my @selected_fields=split(/\t/,$selected_record);
            my ($selected_ref, $null, $gi) = split(/\|/,$selected_fields[2]);
            if ($selected_ref eq "VIRL"){
                $selected_ref .= "_$gi";
            }
            $ref_counts_hash{$selected_ref}++;
        } 
    }

    #convert sam to bam
    my $bam_combined_output_file_unsorted = $working_directory."/combined_unsorted.bam";

    $self->status_message("Converting from sam to bam file: ".$self->sam_combined_output_file." to $bam_combined_output_file_unsorted");
    my $picard_path = "/gsc/scripts/lib/java/samtools/picard-tools-1.07/";
    my $cmd_convert = "java -XX:MaxPermSize=512m -Xmx4g -cp $picard_path/SamFormatConverter.jar net.sf.picard.sam.SamFormatConverter VALIDATION_STRINGENCY=SILENT I=".$self->sam_combined_output_file." O=$bam_combined_output_file_unsorted";  
    my $rv_convert = Genome::Utility::FileSystem->shellcmd(cmd=>$cmd_convert);											 

    if ($rv_convert != 1) {
        $self->error_message("<<<Failed CombineAlignments on sam to bam conversion.  Return value: $rv_convert");
        return;
    }

    unless (unlink $self->sam_combined_output_file){
        $self->warning_message("<<<Failed to remove combined sam file ". $self->sam_combined_output_file);
    }

    $self->status_message("Starting bam sort.");
    my $cmd_sort = Genome::Model::Tools::Sam::SortBam->create(file_name=>$bam_combined_output_file_unsorted, output_file=>$bam_combined_output_file);
    my $rv_sort = $cmd_sort->execute;

    if ($rv_sort != 1) {
        $self->error_message("<<<Failed CombineAlignments on sam to bam conversion.  Return value: $rv_convert");
        return;
    }

    unless (unlink $bam_combined_output_file_unsorted){
        $self->warning_message("<<<Failed to remove unsorted bam file ". $bam_combined_output_file_unsorted);
    }

    #do phyla/genus
    my %species_counts_hash;
    my %phyla_counts_hash;
    my %genus_counts_hash;
    my %viral_family_counts_hash;
    my %viral_subfamily_counts_hash;
    my %viral_genus_counts_hash;
    my %viral_species_counts_hash;
    print $read_cnt_o "Reference Name\t#Reads with hits\tPhyla\tHMP genome\n";
    foreach my $ref_id (keys%ref_counts_hash){
        #print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t$g\t$p\n";
        if (($ref_id =~ /^BACT/) or ($ref_id =~ /^ARCH/) or ($ref_id =~ /^EUKY/)){
            my $species= $taxonomy->{$ref_id}->{species};
            $species_counts_hash{$species}+=$ref_counts_hash{$ref_id};
            my $phyla=$taxonomy->{$ref_id}->{phyla};
            $phyla_counts_hash{$phyla}+=$ref_counts_hash{$ref_id};
            my $genus=$taxonomy->{$ref_id}->{genus};
            $genus_counts_hash{$genus}+=$ref_counts_hash{$ref_id};
            my $hmp_flag=$taxonomy->{$ref_id}->{hmp};	
            print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t$phyla\t$hmp_flag\n";
        }elsif ($ref_id =~ /^VIRL/){ #produce reports for viral taxonomy if available
            my ($gi) = $ref_id =~/^VIRL_(\d+)$/;
            if ($viral_taxonomy->{$gi}){
                my $species = $viral_taxonomy->{$gi}->{species};
                $viral_species_counts_hash{$species}+=$ref_counts_hash{$ref_id};
                my $genus = $viral_taxonomy->{$gi}->{genus};
                $viral_genus_counts_hash{$genus}+=$ref_counts_hash{$ref_id};
                my $family = $viral_taxonomy->{$gi}->{family};
                $viral_family_counts_hash{$family}+=$ref_counts_hash{$ref_id};
                my $subfamily = $viral_taxonomy->{$gi}->{subfamily};
                $viral_subfamily_counts_hash{$subfamily}+=$ref_counts_hash{$ref_id};
                print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t$species\t\n";
            }else{
                print $read_cnt_o "$ref_id\t$ref_counts_hash{$ref_id}\t\t\n";
            }
        }

    }
    $read_cnt_o->close;

    print $phyla_o "Phyla Name\t#Reads with hits\n";
    foreach my $phy (keys%phyla_counts_hash){
        next if (($phy eq "") or ($phy =~ /^\s+$/));
        print $phyla_o "$phy\t$phyla_counts_hash{$phy}\n";
    }
    $phyla_o->close;

    print $genus_o "Genus Name\t#Reads with hits\n";
    foreach my $gen (keys%genus_counts_hash){
        next if (($gen eq "") or ($gen =~ /^\s+$/));
        print $genus_o "$gen\t$genus_counts_hash{$gen}\n";
    }
    $genus_o->close;

    print $viral_species_o "Species Name\t#Reads with hits\n";
    foreach my $name (keys%viral_species_counts_hash){
        next if (($name eq "") or ($name =~ /^\s+$/));
        print $viral_species_o "$name\t$viral_species_counts_hash{$name}\n";
    }
    $viral_species_o->close;
    
    print $viral_genus_o "Genus Name\t#Reads with hits\n";
    foreach my $name (keys%viral_genus_counts_hash){
        next if (($name eq "") or ($name =~ /^\s+$/));
        print $viral_genus_o "$name\t$viral_genus_counts_hash{$name}\n";
    }
    $viral_genus_o->close;
    
    print $viral_family_o "Family Name\t#Reads with hits\n";
    foreach my $name (keys%viral_family_counts_hash){
        next if (($name eq "") or ($name =~ /^\s+$/));
        print $viral_family_o "$name\t$viral_family_counts_hash{$name}\n";
    }
    $viral_family_o->close;
    
    print $viral_subfamily_o "Subfamily Name\t#Reads with hits\n";
    foreach my $name (keys%viral_subfamily_counts_hash){
        next if (($name eq "") or ($name =~ /^\s+$/));
        print $viral_subfamily_o "$name\t$viral_family_counts_hash{$name}\n";
    }
    $viral_subfamily_o->close;

    Genome::Utility::FileSystem->mark_files_ok(input_files=>\@expected_output_files);

    $now = UR::Time->now;
    $self->status_message("<<<Ending CombineAlignments execute() at ".UR::Time->now); 

    $self->bam_combined_output_file($bam_combined_output_file);

    return 1;
}
1;

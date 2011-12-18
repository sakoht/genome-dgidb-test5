package Genome::Model::Tools::Vcf::Convert::Base;

use strict;
use warnings;
use Genome;
use POSIX 'strftime';

class Genome::Model::Tools::Vcf::Convert::Base {
    is => 'Command',
    is_abstract => 1,
    has => [
    output_file => {
        is => 'Text',
        doc => "List of mutations, converted to VCF",
    },
    input_file => {
        is => 'Text',
        doc => "The file to be converted to VCF" ,
    },
    aligned_reads_sample => {
        is => 'Text',
        doc => "The label to be used for the aligned_reads sample in the VCF header",
    },
    control_aligned_reads_sample => {
        is => 'Text',
        doc => "The label to be used for the aligned_reads sample in the VCF header",
        is_optional => 1,
    },
    reference_sequence_build => {
        is => 'Genome::Model::Build::ImportedReferenceSequence',
        doc => 'The reference sequence build used to detect variants',
        id_by => 'reference_sequence_build_id',
    },
    reference_sequence_input => {
        is_constant => 1,
        calculate_from => ['reference_sequence_build'],
        calculate => q|
        my $cache_base_dir = $reference_sequence_build->local_cache_basedir;
        if ( -d $cache_base_dir ) { # WE ARE ON A MACHINE THAT SUPPORTS CACHING
        return $reference_sequence_build->cached_full_consensus_path('fa');
        }
        else { # USE NETWORK REFERENCE
        return $reference_sequence_build->full_consensus_path('fa');
        }
        |,
        doc => 'Location of the reference sequence file',
    },
    sequencing_center => {
        is => 'Text',
        doc => "Center that did the sequencing. Used to figure out the 'reference' section of the header." ,
        default => "WUSTL",
        valid_values => ["WUSTL", "BROAD"],
    },
    vcf_version => {
        is => 'Text',
        doc => "Version of the VCF being printed" ,
        default => "4.1",
        valid_values => ["4.1"],
    },
    ],
    has_transient_optional => [
    _input_fh => {
        is => 'IO::File',
        doc => 'Filehandle for the source variant file',
    },
    _output_fh => {
        is => 'IO::File',
        doc => 'Filehandle for the output VCF',
    },
    ],

    doc => 'Base class for tools that convert lists of mutations to VCF',
};

sub execute {
    my $self = shift;

    unless($self->initialize_filehandles) {
        return;
    }

    $self->print_header;

    $self->convert_file;

    $self->close_filehandles;

    return 1;
}

sub initialize_filehandles {
    my $self = shift;

    if($self->_input_fh || $self->_output_fh) {
        return 1; #Already initialized
    }

    my $input = $self->input_file;
    my $output = $self->output_file;

    eval {
        my $input_fh = Genome::Sys->open_file_for_reading($input);
        my $output_fh = Genome::Sys->open_gzip_file_for_writing($output);

        $self->_input_fh($input_fh);
        $self->_output_fh($output_fh);
    };

    if($@) {
        $self->error_message('Failed to open file. ' . $@);
        $self->close_filehandles;
        return;
    }

    return 1;
}

sub close_filehandles {
    my $self = shift;

    my $input_fh = $self->_input_fh;
    close($input_fh) if $input_fh;

    my $output_fh = $self->_output_fh;
    close($output_fh) if $output_fh;

    return 1;
}

# Get the base at this position in the reference. Used when an anchor (previous base) is needed for the reference column
sub get_base_at_position {
    my $self = shift;
    my ($chr,$pos) = @_;

    my $reference = $self->reference_sequence_input;
    Genome::Sys->validate_file_for_reading($reference);
    my $sam_default = Genome::Model::Tools::Sam->path_for_samtools_version;
    my $faidx_cmd = "$sam_default faidx $reference $chr:$pos-$pos";

    my $sequence = `$faidx_cmd | grep -v \">\"`;
    unless ($sequence) {
        die $self->error_message("Failed to get a return from running the faidx command: $faidx_cmd");
    }
    chomp $sequence;
    return $sequence;
}

sub _get_header_columns {
    my $self = shift;
    my @header_columns = ("CHROM","POS","ID","REF","ALT","QUAL","FILTER","INFO","FORMAT");
    push @header_columns, ( defined $self->control_aligned_reads_sample ) ? ($self->control_aligned_reads_sample, $self->aligned_reads_sample) : ($self->aligned_reads_sample);
    return @header_columns;
}

# Print the header to the output file... currently assumes "standard" columns of GT,GQ,DP,BQ,MQ,AD,FA,VAQ in the FORMAT field and VT in the INFO field.
sub print_header{
    my $self = shift;
    my $file_date = strftime( "%Y%m%d", localtime);

    my $source = $self->source;

    my $public_reference;
    # Calculate the location of the public reference sequence
    my $seq_center = $self->sequencing_center;
    my $reference_sequence_version = $self->reference_sequence_build->version;
    my $subject = $self->reference_sequence_build->subject_name;

    if ($subject eq "human") {
        if ($reference_sequence_version == 37) {
            $public_reference = "ftp://ftp.ncbi.nih.gov/genbank/genomes/Eukaryotes/vertebrates_mammals/Homo_sapiens/GRCh37/special_requests/GRCh37-lite.fa.gz";
        } elsif ($reference_sequence_version == 36) {
            if ($seq_center eq "WUSTL"){
                $public_reference = "ftp://ftp.ncbi.nlm.nih.gov/genomes/H_sapiens/ARCHIVE/BUILD.36.3/special_requests/assembly_variants/NCBI36_WUGSC_variant.fa.gz";
            } elsif ($seq_center eq "BROAD"){
                $public_reference="ftp://ftp.ncbi.nlm.nih.gov/genomes/H_sapiens/ARCHIVE/BUILD.36.3/special_requests/assembly_variants/NCBI36-HG18_Broad_variant.fa.gz";
            } else {
                die $self->error_message("Unknown sequencing center: $seq_center");
            }
        } else {
            die $self->error_message("Unknown reference sequence version ($reference_sequence_version) from reference sequence build " . $self->reference_sequence_build_id);
        }
    } else {
        # TODO We need a map from internal reference to external references... until then just put our reference in there
        $public_reference = $self->reference_sequence_input;
    }


    my $output_fh = $self->_output_fh;

    my $sample = $self->aligned_reads_sample;

    $output_fh->print("##fileformat=VCFv" . $self->vcf_version . "\n");
    $output_fh->print("##fileDate=" . $file_date . "\n");
    $output_fh->print("##source=" . $source . "\n");
    $output_fh->print("##reference=$public_reference" . "\n");
    $output_fh->print("##phasing=none" . "\n");

    $self->print_tag_meta;

    my @header_columns = $self->_get_header_columns;

    #column header:
    $output_fh->print( "#" . join("\t", @header_columns) . "\n");
    return 1;
}

# Print the FORMAT and INFO meta information lines which are part of the header
sub print_tag_meta {
    my $self = shift;
    my $output_fh = $self->_output_fh;

    my @tags = $self->get_format_meta;
    push @tags, $self->get_info_meta;

    for my $tag (@tags) {
        my $string = $self->format_meta_line($tag);
        $output_fh->print("$string\n");
    }

    return 1;
}

# Return an array of hashrefs describing the meta information for FORMAT fields
sub get_format_meta {
    my $self = shift;

    my $gt = {MetaType => "FORMAT", ID => "GT", Number => 1, Type => "String", Description => "Genotype"};
    my $gq = {MetaType => "FORMAT", ID => "GQ", Number => 1, Type => "Integer", Description => "Genotype Quality"};
    my $dp = {MetaType => "FORMAT", ID => "DP", Number => 1, Type => "Integer", Description => "Total Read Depth"};
    my $bq = {MetaType => "FORMAT", ID => "BQ", Number => "A", Type => "Integer", Description => "Average Base Quality corresponding to alternate alleles 1/2/3... after software and quality filtering"};
    my $mq = {MetaType => "FORMAT", ID => "MQ", Number => 1, Type => "Integer", Description => "Average Mapping Quality"};
    my $ad = {MetaType => "FORMAT", ID => "AD", Number => "A", Type => "Integer", Description => "Allele Depth corresponding to alternate alleles 1/2/3... after software and quality filtering"};
    my $fa = {MetaType => "FORMAT", ID => "FA", Number => 1, Type => "Float", Description => "Fraction of reads supporting ALT"};
    my $vaq = {MetaType => "FORMAT", ID => "VAQ", Number => 1, Type => "Integer", Description => "Variant Quality"};

    return ($gt, $gq, $dp, $bq, $mq, $ad, $fa, $vaq);
}

# Return an array of hashrefs describing the meta information for INFO fields
sub get_info_meta {
    my $self = shift;

    # We currently have no INFO fields that are desired in every VCF for snvs (Variant Type) is currently considered redundant
    return;
}

# Given a hashref representing one meta line, return a formatted line for printing in the header
sub format_meta_line {
    my $self = shift;
    my $tag = shift;

    $self->validate_meta_tag($tag);

    my $string = sprintf("##%s=<ID=%s,Number=%s,Type=%s,Description=\"%s\">", $tag->{MetaType}, $tag->{ID}, $tag->{Number}, $tag->{Type}, $tag->{Description});

    return $string;
}

# Takes in a hashref representing one meta tag from the header and makes sure it has the required information
sub validate_meta_tag {
    my $self = shift;
    my $tag = shift;

    unless (defined $tag->{MetaType} && defined $tag->{ID} && defined $tag->{Number} && defined $tag->{Type} && defined $tag->{Description} ) {
        die $self->error_message("A meta tag must contain MetaType, ID, Number, Type, and Description\nTag: " . Data::Dumper::Dumper $tag);
    }

    unless ($tag->{MetaType} eq "INFO" || $tag->{MetaType} eq "FORMAT") {
        die $self->error_message("MetaType for tags must be INFO or FORMAT. Value found is: " . $tag->{MetaType});
    }

    return 1;
}

# Loop through each input line, parse it, and print it to output
sub convert_file {
    my $self = shift;
    my $input_fh = $self->_input_fh;

    while(my $line = $self->get_record($input_fh)) {
        chomp $line;
        my $output_line = $self->parse_line($line);
        if ($output_line) {
            $self->write_line($output_line);
        }
    }

    return 1;
}

# Get the next data record from the file to be converted
# Default behavior is to simply get the data line by line
# Override if you need a more complex method.
sub get_record {
    my $self = shift;
    my $input_fh = shift;

    return $input_fh->getline;
}

# Print a single line to output
sub write_line {
    my $self = shift;
    my $line = shift;

    my $output_fh = $self->_output_fh;
    print $output_fh "$line\n";

    return 1;
}

# Generates the "GT" field. A 0 indicates matching reference. Any other number indicates matching that variant in the available "alt" alleles.
# I.E. REF: A ALT: C,T ... a A/C call in the GT field would be: 0/1. A C,T call in the GT field would be: 1/2
# alt alleles is an arrayref of  the alleles from the "ALT" column, all calls for this position that don't match the reference.
# genotype alleles is an arrayref of the alleles called at this position for this sample, including those that match the reference
sub generate_gt {
    my ($self, $reference, $alt_alleles, $genotype_alleles) = @_;

    my @gt_string;
    for my $genotype_allele (@$genotype_alleles) {
        my $allele_number;
        if ($genotype_allele eq $reference) {
            $allele_number = 0;
        } else {
            # Find the index of the alt allele that matches this genotype allele, add 1 to offset 0 based index
            for (my $i = 0; $i < scalar @$alt_alleles; $i++) {
                if ($genotype_allele eq @$alt_alleles[$i]) {
                    $allele_number = $i + 1; # Genotype index starts at 1
                }
            }
        }
        unless (defined $allele_number) {
            die $self->error_message("Could not match genotype allele $genotype_allele to any allele from the ALT field");
        }

        push(@gt_string, $allele_number);
    }

    # the GT field is sorted out of convention... you'll see 0/1 but not 1/0
    return join("/", sort(@gt_string));
}

# This method is called when you are joining multiple samples together with potentially different ALT strings.
# It will figure out what the new GT string should be based upon the old GT string, reference, new and old ALT values
# old and new ALT are expected to be comma separated strings (as in VCF files).
# old_gt is expected to be the / separated list (0/1) found in VCF files.
sub regenerate_gt {
    my ($self, $reference, $old_alt, $old_gt, $new_alt) = @_;

    my @old_alt = split(",", $old_alt);
    my @old_gt = split("/", $old_gt);

    # Translate the old GT string into a list of alleles that sample contained
    my @alleles;
    for my $genotype_number (@old_gt) {
        my $allele;
        if ($genotype_number == 0) {
            $allele = $reference;
        } else {
            $allele = $old_alt[$genotype_number - 1]; # Genotype number will be 1 based in regards to the alt string
            unless (defined $allele) {
                die $self->error_message("Could not match genotype number $genotype_number to any allele from the ALT field $old_alt");
            }
        }

        push(@alleles, $allele);
    }

    # Now that we have the list of alternate alleles from the original line/ALT ... calculate what the new GT string should be based upon the new ALT
    my @new_alt_alleles = split(",", $new_alt);

    return $self->generate_gt($reference, \@new_alt_alleles, \@alleles);
}

# This method should be overridden by each subclass. It should take in a single detector line and return a single VCF line representing that detector line
sub parse_line {
    my $self = shift;

    die $self->error_message('The parse_line() method should be implemented by subclasses of this module.');
}

# This method (or property) should be overridden by each subclass. It should return a string indicating the detector that produced the vcf
sub source {
    my $self = shift;

    die $self->error_message("The source() method should be implemented by subclasses of this module.");
}

1;


sub normalize_indel_location {
    my $self=shift;
    my $chr = shift;
    my $base_before_event = shift;
    my $ref = shift; #include all deleted bases if deletion
    my $var = shift;  #include all inserted bases if insertion, not needed otherwis
    my $buffer_size = 200;
    my $array_start = $base_before_event - $buffer_size;  
    if(length($ref) > length($var)) { 
        if (substr($ref,0,1) eq substr($ref, -1, 1)) {
            #normalization possible
            $self->status_message("normalizing indel...");  
        } 
        else {
            #we know this won't normalize, skip the compute heavy process
            return($chr, $base_before_event, $ref, $var); 
        }
    }
    elsif(length($var) > length($ref)) {
        if (substr($var,0,1) eq substr($var, -1, 1)) {
            #normalization possible
            $self->status_message("normalizing indel...");  
        }
        else {
            #we know this won't normalize, skip the compute heavy process
            return($chr, $base_before_event, $ref, $var); 
        }
    }


        my $sam_default = Genome::Model::Tools::Sam->path_for_samtools_version;
        my $reference = $self->reference_sequence_input;
        my $faidx_cmd = "$sam_default faidx $reference $chr:$array_start-$base_before_event";
        my $sequence = `$faidx_cmd | grep -v \">\"`;
        $sequence =~ s/\n//g;


        my $prev_base_array_idx = $base_before_event  - $array_start; 
        if(length($ref) > length($var)) { 
            #if deletion on reference test with sequence
            #AGTGTGTGTGTA
            #AGTGTGT--GTA want A--GTGTGTGT 
            #original line would be 
            #test	8	9   GT  0
            $ref = substr($ref, 1); #knock off reference base vcf adds
            my @allele = split //,$ref;
            my $preceding_ref_base = substr $sequence,$prev_base_array_idx,1;
            while($allele[-1] eq $preceding_ref_base) {
                #TODO do some error checking here on the coordinates or we will probably screw some poop up
                unshift @allele, pop @allele; #rotate the allele string
                $prev_base_array_idx--; 
                $preceding_ref_base = substr $sequence,$prev_base_array_idx, 1;

            }
            $ref = $preceding_ref_base;
            $ref .= join(q{},@allele);
        }
        elsif(length($var) > length($ref)) {

            #if insertion like say NPM1
            #
            #ATGCAT****GCATG
            #ATGCATGCATGCATG
            #
            #the original line would be
            #test	6	7	0	GCAT
            $var = substr($var, 1);
            my @allele = split //,$var;
            my $preceding_ref_base = substr $sequence,$prev_base_array_idx,1;
            while($allele[-1] eq $preceding_ref_base) {
                #TODO do some error checking here on the coordinates or we will probably screw some poop up
                unshift @allele, pop @allele; #rotate the allele string
                $prev_base_array_idx--; 
                $preceding_ref_base = substr $sequence,$prev_base_array_idx,1;
            }
            $var = $preceding_ref_base;
            $var .= join(q{},@allele);

        }
        else {
            $self->error_message("This line was not an indel: $chr\t$base_before_event\t$ref\t$var");
        }
        $base_before_event-=($buffer_size - $prev_base_array_idx); 
        return($chr, $base_before_event, $ref, $var);

    }



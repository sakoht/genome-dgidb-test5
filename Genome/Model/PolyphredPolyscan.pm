package Genome::Model::PolyphredPolyscan;

use strict;
use warnings;
use IO::File;
use File::Copy "cp";
use File::Basename;
use Data::Dumper;
use Genome;
use Genome::Utility::ComparePosition qw/compare_position compare_chromosome/;


class Genome::Model::PolyphredPolyscan {
    is => 'Genome::Model',
    has => [
        processing_profile => {
            is => 'Genome::ProcessingProfile::PolyphredPolyscan',
            id_by => 'processing_profile_id'
        },
        sensitivity => { 
            via => 'processing_profile',
            doc => 'The processing param set used', 
        },
        research_project => { 
            via=> 'processing_profile',
            doc => 'research project that this model belongs to', 
        },
        technology=> { 
            via=> 'processing_profile',
            doc => 'The processing param set used', 
        },
    ],
    has_optional => [
        combined_input_fh => {
            is  =>'IO::Handle',
            doc =>'file handle to the combined input file',
        },
        current_pcr_product_genotype => {
            is => 'Hash',
            doc => 'The current pcr product genotype... used for "peek" like functionality',
        },
    ],
};

sub create{
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    
    my $data_dir = $self->data_directory;

    # If the data directory was not supplied, resolve what it should be by default
    unless ($data_dir) {
        $data_dir= $self->resolve_data_directory;
        $self->data_directory($data_dir);
    }
    
    # Replace spaces with underscores
    $data_dir =~ s/ /_/g;
    $self->data_directory($data_dir);

    # Make the model directory
    if (-d $data_dir) {
        $self->error_message("Data directory: " . $data_dir . " already exists before creation");
        return undef;
    }
    
    mkdir $data_dir;

    unless (-d $data_dir) {
        $self->error_message("Failed to create data directory: " . $data_dir);
        return undef;
    }

    #make required non-build directories
    mkdir $self->pending_instrument_data_dir;
    unless (-d $self->pending_instrument_data_dir) {
        $self->error_message("Failed to create instrument data directory: " . $self->pending_instrument_data_dir);
        return undef;
    }
    
    mkdir $self->source_instrument_data_dir;
    unless (-d $self->source_instrument_data_dir) {
        $self->error_message("Failed to create source instrument data directory: " . $self->source_instrument_data_dir);
        return undef;
    }

    return $self;
}

sub build_subclass_name {
    return 'polyphred polyscan';
}

sub type{
    my $self = shift;
    return $self->name;
}

# Returns the default location where this model should live on the file system
sub resolve_data_directory {
    my $self = shift;

    my $base_directory = "/gscmnt/834/info/medseq/polyphred_polyscan/";
    my $name = $self->name;
    my $data_dir = "$base_directory/$name/";
    
    # Remove spaces so the directory isnt a pain
    $data_dir=~ s/ /_/;

    return $data_dir;
}

sub combined_input_file {
    my $self = shift;

    my $data_dir = $self->data_directory;
    my $combined_input_file_name = "$data_dir/combined_input.tsv";

    return $combined_input_file_name;
}

# Takes in an array of pcr product genotypes and finds the simple majority vote for a genotype
# For that sample and position among all pcr products
sub predict_genotype{
    my ($self, @genotypes) = @_;

    # Check for input
    unless (@genotypes){
        $self->error_message("No pcr product genotypes passed in");
        die;
    }
    # If there is only one input, it is the answer
    if (@genotypes == 1){
        return shift @genotypes;
    # Otherwise take a majority vote for genotype among the input
    }else{
        my %genotype_hash;
        foreach my $genotype (@genotypes){
            push @{$genotype_hash{$genotype->{allele1}.$genotype->{allele2} } }, $genotype;
        }
        my $max_vote=0;
        my $dupe_vote=0;
        my $genotype_call;
        foreach my $key (keys %genotype_hash){
            if ($max_vote <= scalar @{$genotype_hash{$key} }){
                $dupe_vote = $max_vote;
                $max_vote = scalar @{$genotype_hash{$key}};
                $genotype_call = $key;
            }
        }
        # If there is no majority vote, the genotype is X X
        if ($max_vote == $dupe_vote){
            my $return_genotype = shift @genotypes;  
            $return_genotype->{allele1} = 'X';
            $return_genotype->{allele2} = 'X';
            foreach my $val( qw/variant_type allele1_type allele2_type score read_count/){
                $return_genotype->{$val} = '-';
            }
            return $return_genotype;
        # Otherwise, return the majority vote     
        }else{
            my $read_count=0;
            foreach my $genotype (@{$genotype_hash{$genotype_call}}){
                $read_count += $genotype->{read_count};
            }
            my $return_genotype = shift @{$genotype_hash{$genotype_call}};
            $return_genotype->{read_count} = $read_count;
            return $return_genotype;
        }
    }
}

# Returns the next line of raw data (one pcr product)
sub next_pcr_product_genotype{
    my $self = shift;
 
    unless ($self->combined_input_fh) {
        $self->setup_input;
    }

    my $fh = $self->combined_input_fh;

    unless ($fh) {
        $self->error_message("Combined input file handle not defined after setup_input");
        die;
    }

    my $line = $fh->getline;
    return undef unless $line;
    my @values = split("\t", $line);

    my $genotype;
    for my $column ($self->combined_input_columns) {
        $genotype->{$column} = shift @values;
    }

    return $genotype;
}

# Returns the genotype for the next position for a sample...
# This takes a simple majority vote from all pcr products for that sample and position
sub next_sample_genotype {
    my $self = shift;

    my @sample_pcr_product_genotypes;
    my ($current_chromosome, $current_position, $current_sample);
    
    # If we have a genotype saved from last time... grab it to begin the new sample pcr product group
    if ($self->current_pcr_product_genotype) {
        push @sample_pcr_product_genotypes, $self->current_pcr_product_genotype;
        $self->current_pcr_product_genotype(undef);
    }
    
    # Grab all of the pcr products for a position and sample
    while ( my $genotype = $self->next_pcr_product_genotype){
        my $chromosome = $genotype->{chromosome};
        my $position = $genotype->{start};
        my $sample = $genotype->{sample_name};

        $current_chromosome ||= $chromosome;
        $current_position ||= $position;
        $current_sample ||= $sample;

        # If we have hit a new sample or position, rewind a line and return the genotype of what we have so far
        if ($current_chromosome ne $chromosome || $current_position ne $position || $current_sample ne $sample) {
            my $new_genotype = $self->predict_genotype(@sample_pcr_product_genotypes);
            $self->current_pcr_product_genotype($genotype);
            return $new_genotype;
        }

        push @sample_pcr_product_genotypes, $genotype;
    }

    # If the array is empty at this point, we have reached the end of the file
    if (scalar(@sample_pcr_product_genotypes) == 0) {
        return undef;
    }

    # Get and return the genotype for this position and sample
    my $new_genotype = $self->predict_genotype(@sample_pcr_product_genotypes);
    return $new_genotype;
}

# Returns the latest complete build number
sub current_version{
    my $self = shift;
    my $archive_dir = $self->data_directory;
    my @build_dirs = `ls $archive_dir`;

    # If there are no previously existing archives
    my $version = 0;
    for my $dir (@build_dirs){
        $version++ if $dir =~/build_\d+/;
    }
    return $version;

    @build_dirs = sort {$a <=> $b} @build_dirs;
    my $last_archived = pop @build_dirs;
    my ($current_version) = $last_archived =~ m/build_(\d+)/;
    return $current_version;
}

# Returns the next available build number
sub next_version {
    my $self = shift;
    
    my $current_version = $self->current_version;
    return $current_version + 1;
}

# Returns the full path to the current build dir
sub current_build_dir {
    my $self = shift;

    my $data_dir = $self->data_directory;
    my $current_version = $self->current_version;
    my $current_build_dir = "$data_dir/build_$current_version/";

    # Remove spaces, replace with underscores
    $current_build_dir =~ s/ /_/;

    unless (-d $current_build_dir) {
        $self->error_message("Current build dir: $current_build_dir doesnt exist");
        return undef;
    }
    
    return $current_build_dir if -d $current_build_dir;
    $self->error_message("current_build_dir $current_build_dir does not exist.  Something has gone terribly awry!");
    die;

}

# Returns full path to the input data in the current build
sub current_instrument_data_dir {
    my $self = shift;
    my $current_build_dir = $self->current_build_dir;

    my $current_instrument_data_dir = "$current_build_dir/instrument_data/";

    # Remove spaces, replace with underscores
    $current_instrument_data_dir =~ s/ /_/;
    
    return $current_instrument_data_dir;
}

# Returns an array of the files in the current input dir
sub current_instrument_data_files {
    my $self = shift;

    my $current_instrument_data_dir = $self->current_instrument_data_dir;
    my @current_instrument_data_files = `ls $current_instrument_data_dir`;
    
    foreach my $file (@current_instrument_data_files){  #gets rid of the newline from ls, remove this if we switch to IO::Dir
        $file = $current_instrument_data_dir . $file;
        chomp $file;
    }

    return @current_instrument_data_files;
}

# Returns the full path to the pending input dir
sub pending_instrument_data_dir {
    my $self = shift;

    my $data_dir = $self->data_directory;
    my $pending_instrument_data_dir = "$data_dir/instrument_data/";

    # Remove spaces, replace with underscores
    $pending_instrument_data_dir =~ s/ /_/;

    return $pending_instrument_data_dir;
}

# Returns an array of the files in the pending input dir
sub pending_instrument_data_files {
    my $self = shift;

    my $pending_instrument_data_dir = $self->pending_instrument_data_dir;
    my @pending_instrument_data_files = `ls $pending_instrument_data_dir`;

    foreach my $file (@pending_instrument_data_files){  #gets rid of the newline from ls, remove this if we switch to IO::Dir
        $file = $pending_instrument_data_dir . $file;
        chomp $file;
    }

    return @pending_instrument_data_files;
}

# Returns the full path to the next build dir that should be created
sub next_build_dir {
    my $self = shift;

    my $data_dir = $self->data_directory;
    my $next_version = $self->next_version;
    my $next_build_dir = "$data_dir/build_$next_version/";

    # Remove spaces, replace with underscores
    $next_build_dir =~ s/ /_/;

    # This should not exist yet
    if (-e $next_build_dir) {
        $self->error_message("next build dir: $next_build_dir already exists (and shouldnt)");
        return undef;
    }
    
    return $next_build_dir;
}

sub source_instrument_data_dir {
    my $self = shift;
    my $data_dir = $self->data_directory;
    my $dir_name = 'source_instrument_data';
    my $dir = "$data_dir/$dir_name";
    
    # Remove spaces, replace with underscores
    $dir =~ s/ /_/;

    return $dir;
}

# List of columns present in the combined input file
sub combined_input_columns {
    my $self = shift;
    return qw(
        chromosome 
        start 
        stop 
        sample_name
        pcr_product_name
        variation_type
        reference
        allele1 
        allele1_type 
        allele2 
        allele2_type 
        con_pos
        num_reads1
        num_reads2
        score
    );
    #poly_score
}

# Grabs all of the input files from the current build, creates MG::IO modules for
# each one, grabs all of their snps and indels, and stuffs them into class variables
sub setup_input {
    my $self = shift;

    my @input_files = $self->current_instrument_data_files;

    # Determine the type of parser to create
    my $type;
    if ($self->technology =~ /polyphred/i) {
        $type = 'Polyphred';
    } elsif ($self->technology =~ /polyscan/i) {
        $type = 'Polyscan';
    } else {
        $type = $self->type;
        $self->error_message("Type: $type not recognized.");
        return undef;
    }
    
    # Combined input file to be created from the collates of all input files
    my $combined_input_file = $self->combined_input_file;
    my $fh = IO::File->new(">$combined_input_file");
    
    # Create parsers for each file, append to running lists
    # TODO eliminate duplicates!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    for my $file (@input_files) {
        #TODO make sure assembly project names are going to be kosher
        my ($assembly_project_name) = $file =~ /\/([^\.\/]+)\.poly(scan|phred)\.(low|high)$/;  
        my $param = lc($type);
        my $module = "MG::IO::$type";
        my $parser = $module->new($param => $file,
                                  assembly_project_name => $assembly_project_name
                                 );
        my ($snps, $indels) = $parser->collate_sample_group_mutations;

        # Print all of the snps and indels to the combined input file
        for my $variant (@$snps, @$indels) {
            $fh->print( join("\t", map{$variant->{$_} } $self->combined_input_columns ) );
            $fh->print("\n");
        }
    }

    $fh->close;

    unless (-s $combined_input_file) {
        $self->error_message("Combined input file does not exist or has 0 size in setup_input");
        die;
    }

    system("sort -gk1 -gk2 $combined_input_file");

    # Set up the file handle to be used as input
    my $in_fh = IO::File->new("$combined_input_file");
    $self->combined_input_fh($in_fh);

    return 1;
}

# attempts to get an existing model with the params supplied
sub get_or_create{
    my ($class , %p) = @_;
    
    my $research_project_name = $p{research_project};
    my $technology = $p{technology};
    my $sensitivity = $p{sensitivity};
    my $data_directory = $p{data_directory};
    my $subject_name = $p{subject_name};
    
    unless (defined($research_project_name) && defined($technology) && defined($sensitivity) && defined($subject_name)) {
        $class->error_message("Insufficient params supplied to get_or_create");
        return undef;
    }

    my $pp_name = "$research_project_name.$technology.$sensitivity";
    my $model_name = "$subject_name.$pp_name";

    my $model = Genome::Model::PolyphredPolyscan->get(
        name => $model_name,
    );

    unless ($model){
        my $pp = Genome::ProcessingProfile::PolyphredPolyscan->get(
            name => $pp_name,
            #research_project => $research_project_name,
            #technology => $technology,
            #sensitivity => $sensitivity,
        );
        unless ($pp){
            $pp = Genome::ProcessingProfile::PolyphredPolyscan->create(
                name => $pp_name, 
                research_project => $research_project_name,
                technology => $technology,
                sensitivity => $sensitivity,
            );
        }
        my $create_command = Genome::Model::Command::Create::Model->create(
            model_name => $model_name,
            processing_profile_name => $pp->name,
            subject_name => $subject_name,
            data_directory => $data_directory,
        );

        $model = $create_command->execute();

        unless ($model) {
            $class->error_message("Failed to create model in get_or_create");
            die;
        }

        # Now, get or create the combine variants model and add this newly created model to it
        # TODO: Should be some other parameters besides name as the research project name...
        my $combine_variants_model = Genome::Model::CombineVariants->get_or_create(subject_name => $subject_name);

        $combine_variants_model->add_child_model($model);
    }


    
    return $model;
}

1;

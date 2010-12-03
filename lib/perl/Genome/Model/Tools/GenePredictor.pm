package Genome::Model::Tools::GenePredictor;

use strict;
use warnings;

use Genome;
use File::Temp;
use File::Basename;
use Bio::SeqIO;
use Carp 'confess';

class Genome::Model::Tools::GenePredictor {
    is => 'Command',
    is_abstract => 1,
    has => [
        fasta_file => {
            is => 'Path',
            is_input => 1,
            doc => 'Fasta file (possibly with multiple sequences) to be used by predictor',
        },
        raw_output_directory => {
            is => 'Path',
            is_input => 1,
            doc => 'Raw output of predictor goes into this directory',
        },
        prediction_directory => {
            is => 'Path',
            is_input => 1,
            is_output => 1,
            doc => 'Predictions are written to files in this directory',
        },
    ],
};

sub help_brief {
    return 'Abstract base class for gene prediction modules';
}

sub help_synopsis {
    return 'Abstract base class for gene prediction modules, defines a few parameters';
}

sub help_detail {
    return 'Abstract base class for gene prediction modules, defines input and output parameters';
}

# Returns the name of a temp file in the given directory. If no template is given,
# uses a default (but please supply a template)
sub get_temp_file_in_directory {
    my ($self, $dir, $template) = @_;
    $self->warning_message("No directory found at $dir!") and return unless -d $dir;
    $template = "temp_file_XXXXXX" unless defined $template;
    my $fh = File::Temp->new(
        DIR => $dir,
        TEMPLATE => $template,
        CLEANUP => 0,
        UNLINK => 0,
    );
    my $file = $fh->filename;
    $fh->close;
    chmod(0666, $file);
    return $file;
}

sub valid_prediction_types {
    my $self = shift;
    return qw/ 
       Genome::Prediction::RNAGene 
       Genome::Prediction::CodingGene 
       Genome::Prediction::Transcript 
       Genome::Prediction::Protein 
       Genome::Prediction::Exon
    /;
}

# Searches the fasta file for the named sequence and returns a Bio::Seq object representing it.
# TODO This method can be optimized so it isn't necessary to reread the entire fasta file when
# accessing sequences sequentially, which is usually the case when dealing with predictor output.
sub get_sequence_by_name {
    my ($self, $seq_name) = @_;
    my $seq_obj = Bio::SeqIO->new(
        -file => $self->fasta_file,
        -format => 'Fasta',
    );

    while (my $seq = $seq_obj->next_seq()) {
        return $seq if $seq->display_id() eq $seq_name;
    }

    return;
}

# For the given type, determine if its valid, resolve the file that needs to be locked, and lock it.
sub lock_files_for_predictions {
    my ($self, @types) = @_;
    my @locks;
    for my $type (@types) {
        unless ($self->is_valid_prediction_type($type)) {
            confess "$type is not a valid prediction type!";
        }
    
        my $ds = $type->__meta__->data_source;
        my $file_resolver = $ds->can('file_resolver');
        my $file = $file_resolver->($self->prediction_directory);

        my $resource_lock = "/gsc/var/lock/gene_prediction/eukaryotic/$file";
        my $lock = Genome::Utility::FileSystem->lock_resource(
            resource_lock => $resource_lock,
            block_sleep => 60,
            max_try => 10,
        );
        confess "Could not get lock on $file for type $type!" unless $lock;
        push @locks, $lock;
    }
    return @locks;
}

# Release locks for prediction files
sub release_prediction_locks {
    my ($self, @locks) = @_;
    for my $lock (@locks) {
        Genome::Utility::FileSystem->unlock_resource(
            resource_lock => $lock,
        );
    }
    return 1;
}

sub is_valid_prediction_type {
    my ($self, $type) = @_;
    for my $valid_type ($self->valid_prediction_types) {
        return 1 if $type eq $valid_type;
    }
    return 0;
}
1;

package Genome::InstrumentData::Composite;

use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Composite {
    is => 'UR::Object',
    has => [
        inputs => {
            is => 'HASH',
            doc => 'a mapping from keys in the strategy to their values (the source data and reference sequences to use)',
        },
        strategy => {
            is => 'Text',
            doc => 'The instructions of how the inputs are to be aligned and/or filtered',
        },
        force_fragment => {
            is => 'Boolean',
            default_value => 0,
            doc => 'Treat all reads as fragment reads',
        },
        merge_group => {
            is => 'Text',
            default_value => 'sample',
            valid_values => ['sample', 'all'],
            doc => 'When merging, collect instrument data together that share this property',
        },
        _merged_results => {
            is => 'Genome::InstrumentData::AlignmentResult::Merged',
            is_transient => 1,
            is_optional => 1,
            doc => 'Holds the underlying merged results',
            is_many => 1,
        },
    ],
    has_transient_optional => {
        log_directory => {
            is => 'Text',
            doc => 'where to write the workflow logs',
        },
    },
};

#This method should just use the one from Genome::SoftwareResult and then get will return the existing result and create will run the alignment dispatcher
sub get_or_create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    $self->status_message('Get or create composite instrument data...');

    my $inputs = $self->inputs;
    my $strategy = $self->strategy;

    $self->status_message('Create composite workflow...');
    my $generator = Genome::InstrumentData::Composite::Workflow->create(
        inputs => {
            %{ $self->inputs },
            force_fragment => $self->force_fragment,
        },
        strategy => $self->strategy,
        merge_group => $self->merge_group,
        log_directory => $self->log_directory,
    );
    $self->status_message('Create composite workflow...OK');

    $self->status_message('Execute composite workflow...OK');
    $generator->dump_status_messages(1);
    unless($generator->execute) {
        die $self->error_message('Failed to execute workflow.');
    }
    $self->status_message('Execute composite workflow...OK');

    $self->status_message('Get software results...');
    my @result_ids = $generator->_result_ids;
    my @all_results = Genome::SoftwareResult->get(\@result_ids);
    $self->status_message('Found '.@all_results.' software results');

    #TODO If this is made a result, too, register as a user
    #for my $result (@all_results) {
    #    $result->add_user(label => 'uses', user => $self);
    #}

    my @merged_results = grep($_->class =~ /Merged/, @all_results);
    $self->status_message('Found '.@all_results.' merged results');
    $self->_merged_results(\@merged_results);

    return $self;
}

sub bam_paths {
    my $self = shift;

    my @results = $self->_merged_results;

    my @bams;
    for my $result (@results) {
        my $bam = $result->merged_alignment_bam_path;
        push @bams, $bam;
    }

    return @bams;
}

1;

package Genome::Model::Tools::DetectVariants2::Pindel;

use warnings;
use strict;

use Genome;
use Workflow;
use File::Copy;
use Workflow::Simple;
use Cwd;

my $DEFAULT_VERSION = '0.2';
my $PINDEL_COMMAND = 'pindel_64';

class Genome::Model::Tools::DetectVariants2::Pindel {
    is => ['Genome::Model::Tools::DetectVariants2::Detector'],
    doc => "Runs the pindel pipeline on the last complete build of a somatic model.",
    has => [
        chromosome_list => {
            is => 'ARRAY',
            is_optional => 1,
            doc => 'list of chromosomes to run on.',
        },
    ],
    has_constant_optional => [
        sv_params=>{},
        detect_svs=>{},
        snv_params=>{},
        detect_snvs=>{},
    ],
    has_transient_optional => [
        _workflow_result => {
            doc => 'Result of the workflow',
        },
        _indel_output_dir => {
            is => 'String',
            doc => 'The location of the indels.hq.bed file',
        },
    ],
    has_param => [
        lsf_queue => {
            default_value => 'workflow'
        },
    ],
};



sub _detect_variants {
    my $self = shift;
    # Obtain normal and tumor bams and check them. Either from somatic model id or from direct specification. 
    my ($build, $tumor_bam, $normal_bam);
    $tumor_bam = $self->aligned_reads_input;
    $normal_bam = $self->control_aligned_reads_input if defined $self->control_aligned_reads_input;

    unless(defined($self->reference_sequence_input)){
        $self->reference_sequence_input( Genome::Config::reference_sequence_directory() . '/NCBI-human-build36/all_sequences.fa' );
    }

    # Set default params
    unless ($self->chromosome_list) { $self->chromosome_list([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,'X','Y']); }

    unless ($self->indel_bed_output) { $self->indel_bed_output($self->_temp_staging_directory. '/indels.hq.bed'); }

    my $workflow = Workflow::Operation->create_from_xml(\*DATA);
    my %input;
    $input{chromosome_list}=$self->chromosome_list;
    $input{reference_sequence_input}=$self->reference_sequence_input;
    $input{tumor_bam}=$self->aligned_reads_input;
    $input{normal_bam}=$self->control_aligned_reads_input if defined $self->control_aligned_reads_input;
    $input{output_directory} = $self->output_directory;#$self->_temp_staging_directory;
    $input{version}=$self->version;
    
    $workflow->log_dir($self->output_directory);
    $self->_dump_workflow($workflow);

    my $result = Workflow::Simple::run_workflow_lsf( $workflow, %input);

    unless($result){
        die $self->error_message("Workflow did not return correctly.");
    }
    $self->_workflow_result($result);
    #my $old = $self->_temp_staging_directory."/".$input{indel_bed_output};
    #my $new = $self->_temp_staging_directory."/indels.hq.bed";
    #symlink($old,$new);

    return 1;
}

sub _dump_workflow {
    my $self = shift;
    my $workflow = shift;
    my $xml = $workflow->save_to_xml;
    my $xml_location = $self->output_directory."/workflow.xml";
    my $xml_file = Genome::Sys->open_file_for_writing($xml_location);
    print $xml_file $xml;
    $xml_file->close;
    #$workflow->as_png($self->output_directory."/workflow.png"); #currently commented out because blades do not all have the "dot" library to use graphviz
}

sub _create_temp_directories {
    my $self = shift;
    $self->_temp_staging_directory($self->output_directory);
    $self->_temp_scratch_directory($self->output_directory);
    return 1;

    return $self->SUPER::_create_temp_directories(@_);
}

sub _promote_staged_data {
    my $self = shift;
    my $staging_dir = $self->_temp_staging_directory;
    my $output_dir  = $self->output_directory;
    my @chrom_list = @{$self->chromosome_list};
    my $test_chrom = $chrom_list[0];
    my $bed = $self->output_directory."/".$test_chrom."/indels_all_sequences.bed";
    $bed = readlink($bed);
    my @stuff = split "\\.", $bed;
    my $bed_version = $stuff[-2];

    my $output_file = $output_dir."/indels.hq.".$bed_version.".bed";
    my @inputs = map { $output_dir."/".$_."/indels_all_sequences.bed" } @chrom_list;
    my $cat_cmd = Genome::Model::Tools::Cat->create( dest => $output_file, source => \@inputs);
    unless($cat_cmd->execute){
        $self->error_message("Cat command failed to execute.");
        die $self->error_message;
    }
    my $cwd = getcwd;
    chdir $output_dir;
    Genome::Sys->create_symlink("indels.hq.".$bed_version.".bed", "indels.hq.bed");
    chdir $cwd; 
    return 1;
}

sub _run_converter {
    my $self = shift;
    my $converter = shift;
    my $source = shift;
    
    my $output = $source . '.bed'; #shift; #TODO Possibly create accessors for the bed files instead of hard-coding this
    
    my $command = $converter->create(
        source => $source,
        output => $output, 
        include_normal => 1,
    );
    
    unless($command->execute) {
        $self->error_message('Failed to convert ' . $source . ' to the standard format.');
        return;
    }

    return 1;
}

sub has_version {
    my $self = shift;
    my $version = shift;
    unless(defined($version)){
        $version = $self->version;
    }
    my @versions = Genome::Model::Tools::DetectVariants::Somatic::Pindel->available_pindel_versions;

    for my $v (@versions){
        if($v eq $version){
            return 1;
        }
    }

    return 0;
}




1;

__DATA__
<?xml version='1.0' standalone='yes'?>

<workflow name="Pindel Detect Variants Module">

  <link fromOperation="input connector" fromProperty="normal_bam" toOperation="Pindel" toProperty="control_aligned_reads_input" />
  <link fromOperation="input connector" fromProperty="tumor_bam" toOperation="Pindel" toProperty="aligned_reads_input" />
  <link fromOperation="input connector" fromProperty="output_directory" toOperation="Pindel" toProperty="output_directory" />
  <link fromOperation="input connector" fromProperty="chromosome_list" toOperation="Pindel" toProperty="chromosome" />
  <link fromOperation="input connector" fromProperty="version" toOperation="Pindel" toProperty="version" />
  <link fromOperation="input connector" fromProperty="reference_sequence_input" toOperation="Pindel" toProperty="reference_sequence_input" />

  <link fromOperation="Pindel" fromProperty="output_directory" toOperation="output connector" toProperty="output" />

  <operation name="Pindel" parallelBy="chromosome">
    <operationtype commandClass="Genome::Model::Tools::DetectVariants::Somatic::Pindel" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operationtype typeClass="Workflow::OperationType::Model">
    <inputproperty isOptional="Y">normal_bam</inputproperty>
    <inputproperty isOptional="Y">tumor_bam</inputproperty>
    <inputproperty isOptional="Y">output_directory</inputproperty>
    <inputproperty isOptional="Y">version</inputproperty>
    <inputproperty isOptional="Y">chromosome_list</inputproperty>
    <inputproperty isOptional="Y">reference_sequence_input</inputproperty>

    <outputproperty>output</outputproperty>
    
  </operationtype>

</workflow>

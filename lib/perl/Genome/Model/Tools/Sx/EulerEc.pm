package Genome::Model::Tools::Sx::EulerEc;

use strict;
use warnings;

use Genome;

use Cwd;

our %EULER_PARAMS = (
    kmer_size => {
        is => 'Number',
        doc => 'Kmer size to use',
    },
    min_multi => {
        is => 'Number',
        doc => 'Minimum multiplicity to keep a k-mer (vertex) or (k+1)-mer (edge), depending on the stage of EULER.',
    },
    script => {
        is => 'Boolean',
        doc => 'Show output from subprocesses. Output is suppressed without this option.',
        is_optional => 1,
    },
    debug => {
        is => 'Boolean',
        doc => 'Run the debug version of the code, compiled by \'make debug\'.',
        is_optional => 1,
    },
    verbose => {
        is => 'Boolean',
        doc => 'Show output from subprocesses. Output is suppressed without this option.',
        is_optional => 1,
    },    
);

class Genome::Model::Tools::Sx::EulerEc {
    is => 'Genome::Model::Tools::Sx',
    has => [
        %EULER_PARAMS,
        save_files => { is => 'Boolean', is_optional => 1, doc => 'Save euler output files' },
    ],
};

sub help_brief {
    'Tool to run Error correction program EulerEc.pl',
}

sub execute {
    my $self = shift;

    $self->_init;
    my $cwd = cwd();

    #tmp dir to run EulerEC
    my $euler_dir = Genome::Sys->base_temp_directory;
    for my $set ( 1 .. 2 ) { #run fwd/rev in separate dirs
        Genome::Sys->create_directory( $euler_dir."/$set" );
    }
    $self->status_message("Running EulerEC in $euler_dir");

    #Input reader
    my $reader = $self->_input;
    $self->error_message("Failed to get input file to process") and return
        if not $reader;

    #Euler fasta writer 1
    my $fasta = 'euler.fasta';
    my $one_fasta = $euler_dir.'/1/'.$fasta;
    my $one_writer = Genome::Model::Tools::Sx::PhredWriter->create(
        file => $one_fasta,
        qual_file => $one_fasta.'.qual',
    );
    $self->error_message("Failed to create gmt sx phred-writer for 1 sequences") and return
        if not $one_writer;

    #Euler fasta writer 2 .. only write to if paired
    my $two_fasta = $euler_dir.'/2/'.$fasta;
    my $two_writer = Genome::Model::Tools::Sx::PhredWriter->create(
        file => $two_fasta,
        qual_file => $two_fasta.'.qual',
    );
    $self->error_message("Failed to create gmt sx phred-writer to 2 sequences") and return
        if not $two_writer;

    #write input to writer
    while ( my $seqs = $reader->read ) {
        $one_writer->write( @$seqs[0] );
        $two_writer->write( @$seqs[1] ) if @$seqs[1];
    }

    #run EulerEC
    for my $set ( 1 .. 2 ) {
        #EulerEC outputs to cwd
        chdir $euler_dir."/$set";
        $self->status_message("chdir to ".$euler_dir."/$set to run EulerEC");
        if ( -s 'euler.fasta' ) {
            my $env_var = 'EUSRC=/gsc/pkg/bio/euler/euler-sr-ec-2.0.2 MACHTYPE=x86_64';#set env
            my $cmd = $env_var.' EulerEC.pl euler.fasta '.$self->_euler_cmd_params;
            $self->status_message("Running EulerEC for set $set with command: $cmd");
            ### THS IS DOESN'T SEEM WORK WITH STRINGS OF MULTIPLE SX CMDS WILL LOOK INTO IT ###
            #my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
            #if (! $rv ) {
            #    $self->error_message("Failed to run EulerEc.pl with command: $cmd");
            #    return;
            #}
            my $rv = `$cmd`;
            chdir $cwd;
            $self->status_message("EulerEC output message:\n$rv");
        } else {
            $self->status_message("Skipping running EulerEC for set $set, input fasta is empty");
        }
        chdir $cwd;
        $self->status_message("Switching back to original dir: $cwd");
    }

    #euler 1 output reader
    my $euler_1_seq = $euler_dir."/1/fixed/euler.fasta";
    $self->error_message("Euler output is empty or does not exist: ".$euler_1_seq) and return
        if not -s $euler_1_seq;
    my $euler_1_seq_reader = Genome::Model::Tools::Sx::PhredSeqReader->create(
        file => $euler_1_seq,
    );
    my $one_qual_reader = Genome::Model::Tools::Sx::PhredQualReader->create(
        file => $euler_dir.'/1/euler.fasta.qual',
    );

    #euler 2 output reader if written to
    my $euler_2_seq_reader;
    my $two_qual_reader;
    if ( -s $euler_dir."/2/fixed/euler.fasta" ) {
        $self->status_message("Creating set 2 EulerEC output reader");
        $euler_2_seq_reader = Genome::Model::Tools::Sx::PhredSeqReader->create(
            file => $euler_dir."/2/fixed/euler.fasta",
        );
        $two_qual_reader = Genome::Model::Tools::Sx::PhredQualReader->create(
            file => $euler_dir.'/2/euler.fasta.qual',
        ); 
    }

    #output writer
    my $output_writer = $self->_output;
    $self->error_message("Failed to set output writer") and return if
        not $output_writer;
    
    #write to output .. clean up trimmed/appended reads
    while ( my $seq = $euler_1_seq_reader->read ) {
        my $qual = $one_qual_reader->read;
        my $fastq = $self->_fastq_from_seq_qual($seq,$qual);
        $self->error_message("Failed to get fastq from seq and qual") and return
            if not $fastq;
        my @fastqs;
        push @fastqs, $fastq;

        if ( $euler_2_seq_reader ) {
            $seq = $euler_2_seq_reader->read;
            $qual = $two_qual_reader->read;
            $fastq = $self->_fastq_from_seq_qual($seq,$qual);
            $self->error_message("Failed to get fastq from seq and qual") and return
                if not $fastq;
            push @fastqs, $fastq;
        }
        $output_writer->write( \@fastqs );
    }

    return 1;
}

sub _euler_cmd_params {
    my $self = shift;

    my $cmd = $self->kmer_size.' -minMult '.$self->min_multi;
    $cmd .= ' -script' if $self->script;
    $cmd .= ' -verbose' if $self->verbose;
    $cmd .= ' -debug' if $self->debug;

    return $cmd;
}

sub _fastq_from_seq_qual {
    my ( $self, $seq, $qual ) = @_;

    #check seq/qual from same read
    $self->status_message('Got read '.$seq->{id}.' from fasta but read '.$qual->{id}.' from qual') and return
        if not $seq->{id} eq $qual->{id};

    #check seq length == qual length
    if ( length($seq->{seq}) != length($qual->{qual}) ) {
        $self->status_message("Fasta and qual lengths do not match for read id: ".$seq->{id});
        #make all sanger 33/phred 0
        $qual->{qual} = '!' x (length($seq->{seq}));
    }
    $seq->{qual} = $qual->{qual}; 
    return $seq;
}

1;

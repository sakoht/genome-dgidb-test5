package Genome::Model::Tools::Fasta::To;

use strict;
use warnings;

use Genome;

use Bio::SeqIO;
use Bio::Seq::Quality;


class Genome::Model::Tools::Fasta::To {
    is           => 'Genome::Model::Tools::Fasta',
    has_optional => [
        qual_val => {
            is      => 'Integer',
            doc     => 'Set quality value if no quality file provided',
            default => 15,
        }
    ],
};


sub help_brief {
    "convert from fasta sequence (and qual files) to different format files"
}


sub help_detail {                           
    return <<EOS 

EOS
}


sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    my $dir  = $self->dir;

    unless (-d $dir) {
        mkdir $dir, 0777;
        unless (-d $dir) {
            $self->error_message("Fail to make dir: $dir");
            return;
        }
    }

    return $self;
}


sub execute {
    my $self  = shift;
    
    my $fa_io   = $self->get_fasta_reader($self->fasta_file);
    my $qual_io = $self->get_qual_reader($self->qual_file)
        if $self->have_qual_file;
        
    my $out_io = $self->get_format_writer($self->out_file, $self->_format_type)
        if $self->_format_type eq 'fastq';
    
    while (my $fa = $fa_io->next_seq) {
        my $qual_val; 
        my $length = $fa->length;

        if ($self->have_qual_file) {
            my $qual = $qual_io->next_seq;
            my ($f_id, $q_id) = ($fa->id, $qual->id);
            
            unless ($f_id eq $q_id) {
                $self->error_message("id of fasta and quality not equal: $f_id <=> $q_id");
                return;
            }
            unless ($fa->length == $qual->length) {
                $self->error_message("length of fasta and quality not equal: $f_id <=> $q_id");
                return;
            }
            
            $qual_val = $qual->qual;
        }
        else {
            $qual_val = [map{$self->qual_val}(1..$length)];
        }
        
        my %params = (
            -seq  => $fa->seq,
            -qual => $qual_val,
            -id   => $fa->id,
            -force_flush => 1,
        );

        my @traces = map{$_*10}(0..$length-1);

        unless ($self->_format_type eq 'fastq') {
            my $outfile = $self->dir.'/'.$fa->id;
            $outfile .= '.phd.1' if $self->_format_type eq 'phd';
            $out_io = $self->get_format_writer($outfile, $self->_format_type);
            $params{-trace} = \@traces;
        }
        
        my $swq = Bio::Seq::Quality->new(%params);
        
        if ($self->_format_type =~ /^(phd|scf)$/) {
            $swq->chromat_file($fa->id);
            $swq->trace_array_max_index($traces[$#traces]);
            $swq->time($self->time) if $self->time;
        }

        my $write_method = $self->write_method;
        
        if ($self->_format_type eq 'scf') {
            my ($param_key, $param_val) = ($self->_param_type, $self->_param_value($swq));
            $out_io->$write_method($param_key => $param_val);
        }
        else {
            $out_io->$write_method($swq);
        }
    }
    return 1;
}


sub get_format_writer {
    return shift->_get_bioseq_writer(@_);
}


sub write_method {
    return 'write_seq';
}


sub list {
    my $self = shift;
    my $io   = $self->get_fasta_reader($self->fasta_file);
    my @list;

    while (my $fa = $io->next_seq) {
        my $id = $fa->id;
        $id .= '.'.$self->_format_type.'.1' if $self->_format_type eq 'phd';
        push @list, $id;
    }

    return @list;
}

1;

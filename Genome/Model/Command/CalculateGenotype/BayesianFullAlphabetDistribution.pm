
package Genome::Model::Command::CalculateGenotype::BayesianFullAlphabetDistribution;

use strict;
use warnings;

use UR;
use Command;

use IO::File;

use constant MATCH              => 0;
use constant MISMATCH           => 1;
use constant REFERENCE_INSERT   => 2;
use constant QUERY_INSERT       => 3;

use Genome::Model::Command::IterateOverRefSeq;
use Genome::Model::Command::CalculateGenotype;

# Class Methods ---------------------------------------------------------------

UR::Object::Class->define(
    class_name => __PACKAGE__,
    is => 'Genome::Model::Command::CalculateGenotype',
    has => [
        result => { type => 'Array', doc => 'If set, results will be stored here instead of printing to STDOUT.' },
        bases_file => { type => 'String', doc => 'The pathname of the binary file containing prb values' },
    ],
);

sub help_brief {
    return "gives the consensus posterior over {A,C,G,T} for every position";
}

sub help_synopsis {
    return <<EOS

EOS
}

sub help_detail {
    return <<"EOS"


EOS
}

# Instance Methods ------------------------------------------------------------

sub execute {
    my($self) = @_;

    our $bases_fh = IO::File->new($self->bases_file);   # Ugly hack until _examine_position can be called as a method
    unless ($bases_fh) {
        $self->error_message("Can't open bases file: $!");
        return undef;
    }

    $self->SUPER::execute(
                          iterator_method => 'foreach_aligned_position',
                          );
}

# note that we have (assume?) no information about Maternal / Paternal phasing of the diploid genotypes
# this means that we only have the diagonal and top half of the matrix of possible diploid genotypes.
# We also assume that there cannot be the '--' genotype as it is illogical?
# As a rule then, always lexographically sort haploid genotypes before combining
#my $POSSIBLE_GENOTYPES = [
#                          qw/
#                                -- -A -C -G -T
#                                   AA AC AG AT
#                                      CC CG CT
#                                         GG GT
#                                            TT
#                            /
#                          ];

#my $INDEX_OF_DIPLOID_FROM_STRING = {};
#@INDEX_OF_DIPLOID_FROM_STRING{ qw/
#    __ _A _C _G _T
#    A_ AA AC AG AT
#    C_ CA CC CG CT
#    G_ GA GC GG GT
#    T_ TA TC TG TT
#    /} = @$INDEX_OF_DIPLOID_FROM_ORDERED_PAIR;

#my $ALPHABET = [qw/ - A C G T /];

my $INDEX_OF_DIPLOD_FROM_ORDERED_PAIR = [
 [    0,  1,   2,   3,  4, ],
 [    1,  5,   6,   7,  8, ],
 [    2,  6,   9,  10, 11, ],
 [    3,  7,  10,  12, 13, ],
 [    4,  8,  11,  13, 14, ],
];

# we should maybe estimate this from known GC content of reference
my ( $BASE_PRIOR, $INSERTION_PRIOR ) = ( .25, .00001 );

my $BASE_CALL_PRIORS = [
                            $INSERTION_PRIOR,
                            $BASE_PRIOR - $INSERTION_PRIOR / 4,
                            $BASE_PRIOR - $INSERTION_PRIOR / 4,
                            $BASE_PRIOR - $INSERTION_PRIOR / 4,
                            $BASE_PRIOR - $INSERTION_PRIOR / 4
                        ];

sub _examine_position {
    my ($self, $alignments) = @_;

    # Deep copy up a fresh one
    my $diploid_genotype_matrix = _calculate_diploid_genotype_priors();

    foreach my $aln (@$alignments){

        my $evidence = 0;
        
        our $bases_fh;
        $aln->{'reads_fh'} = $bases_fh;   # another ugly hack.  $aln's constructor should know about this instead

        my $aln_prob = $aln->{'alignment_probability'};
        my $vector = $aln->{base_probability_vector};
        my $likelihood_matrix_to_or = [];
        
        foreach my $ordering ( 1, 2 ){
        
            foreach my $maternal_allele_alphabet_index (0 .. 4) {
                foreach my $paternal_allele_alphabet_index (0 .. 4){
                    
                    my ($allele_1, $allele_2);
                    if($ordering == 1){
                        ($allele_1, $allele_2) = ($maternal_allele_alphabet_index, $paternal_allele_alphabet_index);
                    }else{
                        ($allele_2, $allele_1) = ($maternal_allele_alphabet_index, $paternal_allele_alphabet_index);
                    }
                   
                    my $prob_this_ordering = .5;
                   
                    my $base_likelihood = $vector->[$allele_1];
                   
                    my $likelihood = $base_likelihood
                                       * $prob_this_ordering
                                       * $aln_prob
                                       * $BASE_CALL_PRIORS->[$allele_2];
                                       
                    my $not_aln_likelihood = $base_likelihood *
                                                $prob_this_ordering
                                               * (1- $aln_prob)
                                               * $BASE_CALL_PRIORS->[$allele_2];
    
                   $evidence += ( $diploid_genotype_matrix->[$allele_1]->[$allele_2]
                                   * $not_aln_likelihood );
                    
                    $likelihood_matrix_to_or->[$allele_1]->[$allele_2] +=
                            $likelihood;
                }
            }

        }
        
        foreach my $i (0 .. 4){
            foreach my $j (0 .. 4){
                $diploid_genotype_matrix->[$i]->[$j] *= $likelihood_matrix_to_or->[$i]->[$j];
                $evidence += $diploid_genotype_matrix->[$i]->[$j];
            }
        }
    
        foreach my $i (0 .. 4){
            foreach my $j (0 .. 4){
                $diploid_genotype_matrix->[$i]->[$j] /= $evidence;
            }
        }
    }

    my $diploid_genotype_vector = [];
    foreach my $i (0 .. 4){
        foreach my $j (0 .. 4){
            $diploid_genotype_vector->[$INDEX_OF_DIPLOD_FROM_ORDERED_PAIR->[$i]->[$j]] += $diploid_genotype_matrix->[$i]->[$j]
        }
    }

    return $diploid_genotype_vector;
}

# Helper Methods --------------------------------------------------------------

sub _calculate_diploid_genotype_priors{
    
    my $DIPLOID_GENOTYPE_PRIORS = [];
    
    my $evidence_normalizer = 0;
    
    # naive OR
    for (my $i = 0 ; $i < 5 ; $i++){
        
        for( my $j = 0 ; $j < 5 ; $j++){
            
            my $joint_prior = $BASE_CALL_PRIORS->[ $i ] * $BASE_CALL_PRIORS->[ $j ];
            
            $DIPLOID_GENOTYPE_PRIORS->[$i]->[$j] += $joint_prior;
        }
    }
    
    # OR Correction
    foreach my $i (0 .. 4){
        foreach my $j (0 .. 4){
            $DIPLOID_GENOTYPE_PRIORS->[$i]->[$j] -= ($DIPLOID_GENOTYPE_PRIORS->[$i]->[$j] ** 2)/2;
            $evidence_normalizer += $DIPLOID_GENOTYPE_PRIORS->[$i]->[$j];
        }
    }
    
    # Normalize
    foreach my $i (0 .. 4){
        foreach my $j (0 .. 4){
            $DIPLOID_GENOTYPE_PRIORS->[$i]->[$j] /= $evidence_normalizer;
        }
    }
    
    return $DIPLOID_GENOTYPE_PRIORS;
}

1;


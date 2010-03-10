package Genome::Model::Tools::Annotate::ChromosomeRegions;

use strict;
use warnings;

use Genome;

use lib '/gsc/var/tmp/Bio-SamTools/lib';
use Bio::DB::Sam::RefCov::Bed;

class Genome::Model::Tools::Annotate::ChromosomeRegions {
    is => ['Command'],
    has_input => [
        anno_db => {
            default_value => 'NCBI-human.combined-annotation',
        },
        version => {
            default_value => '54_36p',
        },
        bed_file => {
        },
        chromosome => {
            is_optional => 1,
        },
        output_directory => {
        },
    ],
    has_output => [
        anno_file => {
            is_optional => 1,
        },
    ],
};

sub execute {
    my $self = shift;

    my ($basename,$dirname,$suffix) = File::Basename::fileparse($self->bed_file,qw/.bed/);

    Genome::Utility::FileSystem->create_directory($self->output_directory);
    my $bed = Bio::DB::Sam::RefCov::Bed->new(file => $self->bed_file);
    my @chromosomes;
    unless ($self->chromosome) {
        @chromosomes = $bed->chromosomes;
    } else {
        push @chromosomes, $self->chromosome;
    }
    for my $chromosome (@chromosomes) {
        $self->chromosome($chromosome);
        $self->anno_file($self->output_directory .'/'. $basename .'_'.$self->chromosome .'.bed');
        my $fh = IO::File->new($self->anno_file,'w');
    
        my @regions = sort{ $a->start <=> $b->start } $bed->chromosome_regions($self->chromosome);
    
        my $ti = Genome::Model->get(name => $self->anno_db)->build_by_version($self->version)->transcript_iterator(chrom_name => $self->chromosome);
        my $transcript_window =  Genome::Utility::Window::Transcript->create(iterator => $ti);

        for my $region (@regions) {
            for my $t ($transcript_window->scroll($region->start,$region->end)){
                my $gene = $t->gene;
                my $gene_name;
                if ($gene) {
                    $gene_name = $gene->name || 'unknown';
                }
                my @sub_structure = $t->ordered_sub_structures;
                for my $ss (@sub_structure){
                    my $ss_region = Bio::DB::Sam::RefCov::Region->new(
                        start => $ss->structure_start,
                        end => $ss->structure_stop,
                        strand => $t->strand,
                    );
                    if ($ss_region->overlaps($region)) {
                        print $fh $t->chrom_name ."\t". $ss->structure_start ."\t". $ss->structure_stop ."\t". $gene_name
                            .':'. $ss->structure_type ."\t". $ss->ordinal ."\t". $t->strand ."\n";
                    }
                }
            }
        }
        $fh->close;
    }
}

1;

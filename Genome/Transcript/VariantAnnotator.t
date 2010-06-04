#!/gsc/bin/perl

use strict;
use warnings;
use Test::More;
use Storable 'retrieve';
use above "Genome";

# The test variants file can hold 1..n variants
# Each variant must have a corresponding annotation
# These annotations are held in three files, one for each type of filter (top, gene, none)
# Annotations in each file are sorted according to respective filter
my ($variants, $annotations) = get_test_data();

# Test annotation output for all provided variants
check_output($variants, $annotations->{none});

# Ensure that prioritization of annotations behaves correctly
check_prioritization($variants, $annotations);

done_testing();
exit;

################################################################################

sub variant_headers {
    return Genome::Model::Tools::Annotate->variant_attributes;
}

sub annotation_headers {
    return (
        variant_headers(),
        Genome::Model::Tools::Annotate->variant_output_attributes,
        Genome::Model::Tools::Annotate->transcript_attributes,
    );
}

sub get_test_data {
    my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Transcript-VariantAnnotator';
    ok (-e $test_dir, "test data directory exists at $test_dir");

    my $test_variants_file = $test_dir . "/variants.tsv";
    ok (-s $test_variants_file, "test variants file exists and has size");

    my @variant_headers = variant_headers();
    my $variant_svr = Genome::Utility::IO::SeparatedValueReader->create(
        input => $test_variants_file,
        headers => \@variant_headers,
        separator => "\t",
        is_regex => 1,
    );
    my @variants = $variant_svr->all;
    ok (scalar @variants > 0, "successfully grabbed variants from file");

    my $none_annotations_file = $test_dir . "/none_annotations.tsv.new";
    ok (-s $none_annotations_file, "annotations with no filter file exists and has size");

    my $top_annotations_file = $test_dir . "/top_annotations.tsv.new";
    ok (-s $top_annotations_file, "annotations with top filter file exists and has size");

    my $gene_annotations_file = $test_dir . "/gene_annotations.tsv.new";
    ok (-s $gene_annotations_file, "annotations with gene filter file exists and has size");

    my %annotations;
    $annotations{none} = retrieve($none_annotations_file);
    $annotations{top} = retrieve($top_annotations_file);
    $annotations{gene} = retrieve($gene_annotations_file);

    ok (scalar @{$annotations{none}} > 0, "succesfully grabbed test annotations for filter \'none\'");
    ok (scalar @{$annotations{top}} > 0, "successfully grabbed test annotations for filter \'top\'");
    ok (scalar @{$annotations{gene}} > 0, "successfully grabbed test annotations for filter \'gene\'");

    return \@variants, \%annotations;
}

sub create_annotator {
    my $annotation_model = Genome::Model->get(name => 'NCBI-human.combined-annotation');
    my $annotation_build = $annotation_model->build_by_version('54_36p_v2');
    my $iterator = $annotation_build->transcript_iterator;
    my $window = Genome::Utility::Window::Transcript->create(
        iterator => $iterator,
        range => 50000,
    );
    my $annotator = Genome::Transcript::VariantAnnotator->create(
        transcript_window => $window,
    );
    return $annotator;
}

sub get_annotations_for_variant {
    my ($variant, $annotations) = @_;
    my @annotations_for_variant;

    for my $anno (@$annotations) {
        if ($anno->{chromosome_name} eq $variant->{chromosome_name} and
            $anno->{start} eq $variant->{start} and
            $anno->{stop} eq $variant->{stop}) 
        {
            push @annotations_for_variant, $anno;
        }
    }

    return @annotations_for_variant;
}

sub check_output {
    my ($variants, $annotations) = @_;
    my $variant_num = 0;

    my $output_annotator = create_annotator();
    ok (defined $output_annotator, "succesfully created variant annotator object");

    for my $variant (@$variants) {
        $variant->{type} = Genome::Model::Tools::Annotate->infer_variant_type($variant);
        my @test_output = get_annotations_for_variant($variant, $annotations);
        my @output = $output_annotator->transcripts(%$variant);
        ok (compare_annotations(\@test_output, \@output), "annotation output matches expected output for variant $variant_num");
        $variant_num++;
    }
}

sub check_prioritization {
    my ($variants, $annotations) = @_;
    for my $filter (qw/ none top gene /) {
        my $annotator = create_annotator();
        my $variant_num = 0;
        for my $variant (@$variants) {
            my @test_output = get_annotations_for_variant($variant, $annotations->{$filter});
            my @output;
            if ($filter eq "none") {
                @output = $annotator->transcripts(%$variant);
            }
            elsif ($filter eq "gene") {
                @output = $annotator->prioritized_transcripts(%$variant);
            }
            elsif ($filter eq "top") {
                my $output = $annotator->prioritized_transcript(%$variant);
                push @output, $output;
            }

            for my $out (@output) {
                for my $key (keys %$variant) {
                    $out->{$key} = $variant->{$key};
                }
            }

            ok (scalar @output == scalar @test_output, "received same number of results as expected " .
                "for variant $variant_num with filter $filter");
            ok (compare_annotations(\@output, \@test_output), "annotation ordering matches expected " .
                "after prioritization for variant $variant_num with filter $filter");
            $variant_num++;
        }
    }
}

sub compare_annotations {
    my ($output, $test_output) = @_;

    for (my $i = 0; $i < scalar @$output; $i++) {
        my $out = $output->[$i];
        my $test = $test_output->[$i];
        for my $key (sort keys %$test) {
            unless ($out->{$key} eq $test->{$key}) {
                print "*** attribute $key : expected-> " . $test->{$key} . " received-> " . $out->{$key} . " ***\n";
                return 0;
            }
        }
    }
    return 1;
}

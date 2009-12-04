package Genome::Model::Tools::Somatic::UploadVariantValidation;

use strict;
use warnings;
use Genome;
use Genome::Info::IUB;

class Genome::Model::Tools::Somatic::UploadVariantValidation{
    is => 'Command',
    has => [
    variant_file => {
        is  => 'String',
        doc => 'The file of somatic pipeline results to be uploaded. This will usually be a high confidence tier 1 or 2 snp file, or a tier 1 indel file from the somatic pipeline.',
    },
    model_id => {
        is => 'Number',
        doc => 'The model id that should be linked to the variant validation. This is manual for now and required.',
    },
    validation_type => {
        is  => 'String',
        doc => 'The type of validation used for the input file. I.E. "Solexa"',
    },
    output_file => {
        is  => 'String',
        doc => 'The output file to contain all of the variants successfully uploaded (will not include variants that could not be uploaded due to lack of matching Genome::Model::Variant)',
    },
    ],
};

sub help_brief {
    "Adds validation results to the variations from the somatic pipeline.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
    gmt somatic upload-variant-validation --variant-file high_confidence_file.out --model-id 12345
EOS
}

sub help_detail {                           
    return <<EOS 
Adds validation results to the variations from the somatic pipeline.
EOS
}

sub execute {
    my $self = shift;
      
    my $variant_fh = IO::File->new($self->variant_file);
    unless ($variant_fh) {
        $self->error_message("Could not open variant file: " . $self->variant_file . " for reading. $!");
        die;
    }

    my $ofh = IO::File->new($self->output_file, "w");
    unless($ofh) {
        $self->error_message("Unable to open " . $self->output_file . " for writing. $!");
        die;
    }

    my $model = Genome::Model->get($self->model_id);
    unless ($model) {
        $self->error_message("Model does not exist for " . $self->model_id . " please use a valid model.");
        die;
    }

    # Go through each line in the variant file and get each annotation line that matches from the annotation file
    # For each line, print it to the output file and upload it to the database
    while (my $line = $variant_fh->getline) {
        my ($chr, $start, $stop, $reference, $variant, $result) = split "\t", $line;
        
        my $variant_already_exists = Genome::Model::Variant->get(
            chromosome       => $chr,
            start_pos        => $start,
            stop_pos         => $stop,
            reference_allele => $reference,
            variant_allele   => $variant
        );
        unless ($variant_already_exists) {
            $self->warning_message("Genome::Model::Variant could not be found. Skipping validation upload for line: $line");
            next;
        }

        # Get the existing "Official" call and change it to the result we have from this validation type
        # TODO: In the future... we might have multiple validation types so we may not always want to replace the official call without further investigation
        my $overall_validation = Genome::Model::VariantValidation->get_or_create(
            variant           => $variant_already_exists,
            validation_type   => 'Official',
            model_id          => $model->id,
        );
        $overall_validation->validation_result($result);

        # Replace any old validation for this type
        my $type_validation = Genome::Model::VariantValidation->get_or_create(
            variant           => $variant_already_exists,
            validation_type   => $self->validation_type,
            model_id          => $model->id,
        );
        $type_validation->validation_result($result);

        unless($overall_validation && $type_validation) {
            $self->error_message("Unable to create overall validation OR type validation");
            $self->error_message("Problem line: $line");
            $ofh->close;
            unlink($self->output_file);
            die;
        }

        $ofh->print($line);
    }

    $ofh->close;
    return 1;
}

1;

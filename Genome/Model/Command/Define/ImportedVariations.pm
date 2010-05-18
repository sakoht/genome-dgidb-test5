package Genome::Model::Command::Define::ImportedVariations;

use strict;
use warnings;

use Genome;

# Define a custom exception that may be caught specifically so that any other type of exception falls through.
use Exception::Class('ImportedVariations');

class Genome::Model::Command::Define::ImportedVariations {
    is => 'Genome::Model::Command::Define',
    has => [variation_file =>
        {
            is => 'Text',
            len => 1000,
            doc => "The full path and filename of the variations file to import."
        }
    ],
    has_optional => [
        model_name => {
            is => 'Text',
            len => 255,
            doc => '$P-$SPECIES_NAME unless otherwise specified.'
        },
        prefix => {
            is => 'Text',
            value => 'dbSnp',
            doc => 'The source of the file, such as "dbSNP".  May not have spaces.'
        },
        processing_profile_name => {
            #is_constant => 1,
            #value => 'chromosome-fastas',
            doc => 'The processing profile takes no parameters, so all imported reference sequence models share the same processing profile instance.'
        },
        species_name => {
            is => 'Text',
            len => 64,
            doc => 'The species name of the reference.  This value must correspond to a species name found in the gsc.organism_taxon table.'
        },
        subject_name => {
            is_optional => 1,
            doc => 'Copied from species_name.'
        },
        subject_type => {
            is_constant => 1,
            value => 'species_name',
            doc => 'All imported reference sequence models use "species_name" for subject type.'
        },
        subject_class_name => {
            is_constant => 1,
            value => 'Genome::Taxon',
            doc => 'All imported reference sequence model subjects are represented by the Genome::Taxon class.'
        },
        version => {
            is => 'Text',
            len => 128,
            doc => 'The version number and/or description of the dbSNP file.  May not have spaces.  This may be, for example '.
                   '"130" or "130_human".'
        },
        on_warning => {
            valid_values => ['prompt', 'exit', 'continue'],
            default_value => 'prompt',
            doc => 'The action to take when emitting a warning.'
        },
        job_dispatch => {
#            default_value => 'apipe',
#            is_constant => 1,
            doc => 'dispatch specification: an LSF queue or "inline"'
        },
        server_dispatch => {
#            default_value => 'long',
#            is_constant => 1,
            doc => 'dispatch specification: an LSF queue or "inline"'
        },
   ],
};

sub help_synopsis {
    return "genome model define imported-reference-sequence --species-name=human --prefix=NCBI --fasta-file=/gscuser/person/fastafile.fasta\n"
}

sub help_detail {
    return "Prepares a fasta file to be used as a new refseq in processing profiles.";
}

sub onErr
{
    my $str = shift @_;
    ImportedReferenceSequenceException->throw('error' => $str);
}

sub onCheck
{
    my $str = shift @_;
    print STDERR $str . "  Go ahead anyway?  (type yes and press enter to do so).\n";
    my $in = <STDIN>;
    if(defined($in))
    {
        chomp $in;
        if($in eq 'yes')
        {
            onWarn($str);
            return;
        }
    }
    ImportedReferenceSequenceException->throw('error' => $str);
}

sub onWarn
{
    my $str = shift @_;
    print STDERR 'Ignoring error: ' . $str . "\n";
}

# Default to bombing out with an error description upon fatal exception
my $err = \&onErr;
# Default to prompting for "yes\n" from stdin upon warning
my $check = \&onCheck;

sub _execute_try {
    my ($self, $news) = @_;
    if(defined($self->prefix) && $self->prefix =~ /\s/)
    {
        $err->("The prefix argument value must not contain spaces.");
    }

    unless(defined($self->model_name) || defined($self->species_name))
    {
        $err->("Either model name or species name must be supplied.  For a new model, species name is always required.");
    }

    # * Verify that species name matches a taxon
    my $taxon;
    if(defined($self->species_name))
    {
        my @taxons = Genome::Taxon->get('species_name' => $self->species_name);
        if($#taxons == -1)
        {
            $err->("No Genome::Taxon found with species name \"" . $self->species_name . "\".");
            return;
        }
        if($#taxons > 0)
        {
            $err->("Multiple Genome::Taxon instances found with species name \"" . $self->species_name . "\".  This code was written " .
                   "with the assumption that species name uniquely identifies each Genome::Taxon instance.  If strain name or " .
                   "another other field is required in addition to species name to uniquely identify some Genome::Taxon instances, " .
                   "this code should be updated to take strain name or whatever other field as an argument in addition to " .
                   "species name.");
            return;
        }
        $taxon = $taxons[0];
    }

    # * Generate a model name if one was not provided
    unless(defined($self->model_name))
    {
        my $transformedSpeciesName = $self->species_name;
        $transformedSpeciesName =~ s/\s/_/g;
        #$self->model_name($self->prefix . '-' . $transformedSpeciesName);
        $self->model_name($self->processing_profile_name."-".$self->species_name."-".$self->version);
        $self->status_message('Generated model name "' . $self->model_name . '".');
    }

    # * Make a model if one with the appropriate name does not exist.  If one does, check whether making a build for it would duplicate an
    #   existing build.
    my @models = Genome::Model->get('name' => $self->model_name);
    my $model;
    print "before ifins\n\n\n";
    if($#models > 0)
    {
        $err->("More than one model (" . $#models . ") found with the name \"" . $self->model_name . "\".");
        die "more than one model";
    }
    elsif($#models == 0)
    {
        # * We're going to want a new build for an existing model, but first we should see if there are already any builds
        #   of the same version for the existing model.  If so, we ask the user to confirm that they really want to make another.
        $model = $models[0];
        if($model->type_name ne 'imported variations')
        {
            $err->("A model with the name \"" . $self->model_name . "\" already exists and is not of the type - imported variations.");
        }
        if(defined($taxon) && ($model->subject_class_name ne 'Genome::Taxon' || $model->subject_id != $taxon->taxon_id))
        {
            $err->("A model with the name \"" . $self->model_name . "\" already exists but has a different subject class name or a " .
                   "subject ID other than that corresponding to the species name supplied.");
        }
        unless(defined($self->version))
        {
            $check->("A model of name \"" . $model->name . "\" exists and imported reference version was not specified.");
        }

=cut

        my @builds;
        foreach my $build (Genome::Model::Build::ImportedReferenceSequence->get(type_name => 'imported reference sequence'))
        {
            if(defined($self->version))
            {
                if(defined($build->version) && $build->version eq $self->version)
                {
                    push @builds, $build;
                }
            }
            else
            {
                if(!defined($build->version))
                {
                    push @builds, $build;
                }
            }
        }
        if($#builds > -1)
        {
            my $errStr = 'The ';
            if($#builds > 0)
            {
                $errStr .= 'builds of ids [' . join(', ', map({$_->build_id()} @builds)) . '] of this model have the same version identifier.';
            }
            else
            {
                $errStr .= 'build of id ' . $builds[0]->build_id . ' of this model has the same version identifier.';
            }
            $check->($errStr);
        }
        $self->status_message('Using existing model of name "' . $model->name . '" and id ' . $model->genome_model_id . '.');
        # Update the model's prefix, version, and fasta_file inputs for the next build of the model
        $model->prefix($self->prefix);
        $model->version($self->version);
        $model->fasta_file($self->fasta_file);

=cut

        print "in if\n";
    }
    else
    {
        print "in else\n";
        # * We need a new model
        # Note: Genome::Model->data_directory is deprecated and therefore not supplied
        my %modelParams = ('subject_type' => $self->subject_type,
                           'subject_name' => $self->subject_name,
                           'subject_class_name' => $self->subject_class_name,
                           'subject_id' => $self->subject_id,
                           'processing_profile_id' => $self->_get_processing_profile_id_for_name,
                           'name' => $self->model_name);
                           #'fasta_file' => $self->fasta_file);
        if(defined($self->version))
        {
            $modelParams{'version'} = $self->version;
        }
        if(defined($self->prefix))
        {
            $modelParams{'prefix'} = $self->prefix;
        }
        print "just before model define!\n";
        #$model = Genome::Model::ImportedVariations->create(%modelParams);

        # let the super class make the model
        my $super = $self->super_can('_execute_body');
        $super->($self,@_);

        print "just after model define!\n";
        $model = $self->result_model_id; 
        if($model)
        {
            print "created model!\n";
            $self->status_message('Created model of name "' . $model->name . '" and id ' . $model->genome_model_id . '.');
        }
        else
        {
            print "failed to created model!\n";
            $err->("Failed to create model.");
        }
        push @$news, $model;
        if(my @problems = $model->__errors__)
        {
            $err->( "Error creating model:\n\t".  join("\n\t", map({$_->desc} @problems)) );
        }
    }
    undef @models;

    # * Create and start the build
    my %buildParams = ('model_id' => $model->genome_model_id);
    if(defined($self->data_directory))
    {
        $buildParams{'data_directory'} = $self->data_directory;
    }
    my $build = Genome::Model::Build->create(%buildParams);
    if($build)
    {
        $self->status_message('Created build of id ' . $build->build_id . ' with data directory "' . $build->data_directory . '".');
    }
    else
    {
        $err->("Failed to create build for model " . $model->genome_model_id . ".");
    }
    push @$news, $build;

    %buildParams = ();
    if(defined($self->server_dispatch))
    {
        $buildParams{'server_dispatch'} = $self->server_dispatch;
    }
    if(defined($self->job_dispatch))
    {
        $buildParams{'job_dispatch'} = $self->job_dispatch ;
    }

    $self->status_message('Starting build.');
    if($build->start(%buildParams))
    {
        $self->status_message('Started build (build is complete if it was run inline).');
    }
    else
    {
        $err->("Failed to start build " . $build->build_id . " for model " . $model->genome_model_id . ".");
    }
}

sub execute {
    my $self = shift;
#    die "This model definition is under construction - rlong\@genome.wustl.edu\n";

    my @news;
    eval
    {
        if(!defined($self->on_warning))
        {
            $err->('on_warning parameter not supplied.');
        }

        if($self->on_warning eq 'prompt')
        {
            $err = \&onErr;
            $check = \&onCheck;
        }
        elsif($self->on_warning eq 'exit')
        {
            $err = \&onErr;
            $check = \&onErr;
        }
        elsif($self->on_warning eq 'continue')
        {
            $err = \&onErr;
            $check = \&onWarn;
        }
        else
        {
            $err->('on_warning parameter value "' . $self->on_warning . '" not supported.');
        }

        $self->_execute_try(\@news);
    };
    if(my $e = Exception::Class->caught('ImportedVariations'))
    {
        foreach my $dynItem (@news)
        {
            $dynItem->delete();
        }
        $self->error_message($e->error);
        return;
    }

    return 1;
}

1;

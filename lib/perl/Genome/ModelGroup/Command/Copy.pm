package Genome::ModelGroup::Command::Copy;

use strict;
use warnings;

use Genome;

class Genome::ModelGroup::Command::Copy {
    is => 'Genome::Command::Base',
    has => [
        from => {
            shell_args_position => 1,
            is => 'Genome::ModelGroup',
            doc => 'the existing group to copy', 
        },
        to => {
            shell_args_position => 2,
            is => 'Text',
            doc => 'the name of the group to create'
        }
    ],
    has_optional => {
        changes => {
            shell_args_position => 3,
            is => 'Text',
            is_many => 1,
            doc => 'property=value change list to make for the new models'
        },
        force_copy_models => {
            is => 'Boolean',
            doc => 'copy all models in the original group even if there is no processing profile change',
        },
        profile_namer => {
            is => 'Perl',
            doc => 'Regex or Perl to set the name of new processing profiles.  The old profile is $o.  The old name is $n.'
        },
        model_namer => {
            is => 'Perl',
            doc => 'Regex or Perl code to set the name of new models.  The old model is $o.  The old name is $n.'
        },
    },
    doc => 'make a new model group from another, varying properties on the model as specified' 
};

sub help_synopsis {
    return <<EOS
genome model-group copy oldgroup newgroup 

genome model-group copy oldgroup newgroup --force-copy-models

genome model-group copy BRC BRC-trim75 read_trimmer_name='by-length' read_trimmer_params='read_length => 75'

genome model-group copy BRC-trim75 BRC-trim50 read_trimmer_params='read_length => 50' -p 's/75/50/' -m 's/75/50' 

EOS
}

sub _wrap_perl_expr {
    my $expr = $_[0];
    return if not defined $expr;
    my $wrapped = qq|
        sub {
            my (\$o,\$n) = \@_;
            \$_ = \$n;
            my \$c = sub { 
                $expr
            };
            my \$result = \$c->();
            if (\$result eq '1' and \$_ ne \$n) {
                return \$_;
            }
            else {
                return \$result;
            }
        }
    |;
    my $sub = eval $wrapped;
    if ($@) {
        die "Error in code to set the name of processing profiles: $@";
    }
    return $sub;
}

sub execute {
    my $self = shift;

    my $from = $self->from;
    my $to_name = $self->to;
    my @changes = $self->changes;

    my $to = Genome::ModelGroup->get(name => $to_name);
    if ($to) {
        die $self->error_message("model group $to_name exists!: " . $to->__display_name__);
    }

    my $profile_namer = _wrap_perl_expr($self->profile_namer);
    my $model_namer = _wrap_perl_expr($self->model_namer);

    my @from_models = $from->models;

    my %pp_mapping;
    if (@changes) {
        my @from_profiles = sort map { $_->processing_profile } @from_models;
        my $last_profile;
        for my $from_profile (@from_profiles) {
            next if $last_profile and $last_profile == $from_profile;
            $self->status_message("previous processing profile: " . $from_profile->__display_name__ . ":");
            $last_profile = $from_profile;

            my @prev = map { $_->name => $_->value } $last_profile->params();
            my %prev = @prev;
            delete $prev{supercedes};
            delete $prev{reference_sequence_name};

            my $bx = UR::BoolExpr->resolve_for_string($from_profile->class,join(",",@changes));
            my %changes = $bx->params_list;
            delete $changes{-order};
            delete $changes{-hints};
            delete $changes{-page};
            
            for my $name (sort keys %changes) {
                my $prev = $prev{$name};
                my $new = $changes{$name};
                no warnings;
                if ($prev ne $new) {
                    $self->status_message(" changing $name from '$prev' to '$new'");
                }
                else {
                    $self->status_message(" parameter $name already has value '$new'");
                }
            }

            my $pp_class = $from_profile->class;
            my @new = (%prev,%changes);

            $self->status_message(" checking for existing profiles...");
            my @replacements = $pp_class->_profiles_matching_subclass_and_params(@new, type_name => $from_profile->type_name);
            if (@replacements) {
                no warnings;
                @replacements = sort { $a->id <=> $b->id || $a->id cmp $b->id } @replacements;
                for my $replacement (@replacements) {
                    $self->status_message(" found profile matching the new parameters: " . $replacement->__display_name__);
                }
                $pp_mapping{$from_profile} = $replacements[-1];
                if (@replacements > 1) {
                    $self->status_message(" using " . $replacements[-1]->__display_name__);
                }
            }
            else {
                $self->status_message(" creating a new procesing profile for models in the new group...");
                my $old_name = $from_profile->name;
                my $new_name;
                if ($profile_namer) {
                    $new_name = $profile_namer->($from_profile,$from_profile->name);
                    unless ($new_name) {
                        die "Failed to generate a new name for profile " . $from_profile->__display_name__;
                    }
                }
                else {
                    $new_name = $old_name . " CHANGED by $ENV{USER} for $to_name";
                }
                my @used = Genome::ProcessingProfile->get(name => $new_name);
                if (@used) {
                    my $n = 1;
                    $new_name .= '.1';
                    @used = Genome::ProcessingProfile->get(name => $new_name);
                    while (@used) {
                        $new_name =~ s/\.$n$//;
                        $n++;
                        $new_name .= ".$n";
                        @used = Genome::ProcessingProfile->get(name => $new_name);
                    }
                }
                $self->status_message(" new profile name is $new_name (you should give this a better name)...");
                $self->status_message(" working..."); 
                my $new_profile = $pp_class->create(@new, name => $new_name);
                $self->status_message(" created profile: " . $new_profile->__display_name__);
                $pp_mapping{$from_profile} = $new_profile;
            }
        }
    }

    $to = Genome::ModelGroup->create(name => $to_name);

    my $force_copy_models = $self->force_copy_models;
    my @new_models;
    my $n = 0;
    for my $from_model (@from_models) {
        my $from_profile = $from_model->processing_profile;
        my $to_profile = $pp_mapping{$from_profile};
        my $to_model;
        $n++;
        if ($to_profile or $force_copy_models) {
            my $new_name;
            if ($model_namer) {
                $new_name = $model_namer->($from_model,$from_model->name);
                unless ($new_name) {
                    die "Failed to generate a new name for model " . $from_model->__display_name__;
                }
            }
            else {
                $new_name = $to_name . ".$n." . $from_model->subject_name;
            }
            
            # This should work but there is too much information in the constructor commands.
            
            # $to_model = $from_model->copy(
            #    name => $new_name,
            #    processing_profile => $to_profile
            # );            
            
            # Until fixed, we need to call the command instead of the method:
            Genome::Model::Command::Copy->execute(
                from => $from_model, 
                to => $new_name, 
                model_overrides => ["processing_profile_name=" . $to_profile->name ]
            );

            $to_model = Genome::Model->get(name => $new_name);
            $to_model->build_requested(1);
            push @new_models, $to_model;
        }
        else {
            $self->status_message(" adding model from old group to the new group: " . $from_model->__display_name__);
            $to_model = $from_model;
        }
        $to->add_model_bridge(model => $to_model);
    }
   
    $self->status_message("Monitor this group at: " . Genome::Config->base_web_uri . "/genome/model-group/status.html?id=" . $to->id);

    return 1;
}

1;

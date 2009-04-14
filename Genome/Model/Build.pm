package Genome::Model::Build;

use strict;
use warnings;

use Genome;
use File::Path;
use YAML;

class Genome::Model::Build {
    type_name => 'genome model build',
    table_name => 'GENOME_MODEL_BUILD',
    is_abstract => 1,
    sub_classification_method_name => '_resolve_subclass_name',
    id_by => [
        build_id => { is => 'NUMBER', len => 10 },
    ],
    has => [
        data_directory      => { is => 'VARCHAR2', len => 1000, is_optional => 1 },
        
        model               => { is => 'Genome::Model', id_by => 'model_id' },
        model_id            => { is => 'NUMBER', len => 10, implied_by => 'model', constraint_name => 'GMB_GMM_FK' },
        
        date_scheduled      => { via => 'build_event' },
        
        _creation_event     => { calculate_from => [ 'class', 'build_id' ],
                                calculate => q(
                                        my $build_event = "Genome::Model::Build"->get(build_id => $build_id);
                                        return $build_event;
                                )
        },
        
        disk_allocation     => {
                                calculate_from => [ 'class', 'id' ],
                                calculate => q|
                                    my $disk_allocation = Genome::Disk::Allocation->get(
                                                          owner_class_name => $class,
                                                          owner_id => $id,
                                                      );
                                    return $disk_allocation;
                                |,
        },
        
        software_revision   => { is => 'VARCHAR2', len => 1000, is_optional => 1 },
        
        gold_snp_path       => { via => 'model' },  # this should be updated to have an underlying merged microarray model
                                                    # which could update, and result in a new build
    ],
    has_many_optional => [
    
    from_build_links                  => { is => 'Genome::Model::Build::Link',
                                               reverse_id_by => 'to_build',
                                               doc => 'bridge table entries where this is the "to" build(used to retrieve builds this build is "from")'
                                           },
    from_builds                       => { is => 'Genome::Model::Build',
                                               via => 'from_build_links', to => 'from_build',
                                               doc => 'Genome builds that contribute "to" this build',
                                           },
    to_build_links                    => { is => 'Genome::Model::Build::Link',
                                               reverse_id_by => 'from_build',
                                               doc => 'bridge entries where this is the "from" build(used to retrieve builds builds this build is "to")'
                                           },
    to_builds                       => { is => 'Genome::Model::Build',
                                               via => 'to_build_links', to => 'to_build',
                                               doc => 'Genome builds this build contributes "to"',
                                           },
    ], 

    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    unless ($self) {
        return;
    }
    $DB::single = 1;
    unless ($self->data_directory) {
        my $dir;
        eval {
            $dir = $self->resolve_data_directory;
        };
        if ($@) {
            $self->delete;
            return;
        }
        $self->data_directory($dir);
    }
    return $self;
}

sub instrument_data_assignments {
    my $self = shift;

    my @idas = Genome::Model::InstrumentDataAssignment->get(
                                                            model_id => $self->model_id,
                                                            first_build_id => {
                                                                               operator => '<=',
                                                                               value => $self->build_id,
                                                                           },
                                                        );
    return @idas;
}

sub events {
    my $self = shift;

    my @events = Genome::Model::Event->get(
                                           model_id => $self->model_id,
                                           build_id => $self->build_id,
                                       );
    return @events;
}

sub build_events {
    my $self = shift;

    my @build_events = Genome::Model::Command::Build->get(
                                                          model_id => $self->model_id,
                                                          build_id => $self->build_id,
                                                      );
    return @build_events;
}

sub build_event {
    my $self = shift;
    my @build_events = $self->build_events;
    if (scalar(@build_events) > 1) {
        my $error_message = 'Found '. scalar(@build_events) .' build events for model id '.
            $self->model_id .' and build id '. $self->build_id ."\n";
        for (@build_events) {
            $error_message .= "\t". $_->desc .' '. $_->event_status ."\n";
        }
        die($error_message);
    }
    return $build_events[0];
}

sub build_status {
    my $self = shift;

    my $build_event = $self->build_event;
    unless ($build_event) {
        return;
    }
    return $build_event->event_status;
}

sub date_scheduled {
    my $self = shift;

    my $build_event = $self->build_event;
    unless ($build_event) {
        return;
    }
    return $build_event->date_scheduled;
}

sub date_completed {
    my $self = shift;

    my $build_event = $self->build_event;
    unless ($build_event) {
        return;
    }
    return $build_event->date_completed;
}

sub calculate_estimated_kb_usage {
    my $self = shift;
    return;
}

sub resolve_data_directory {
    my $self = shift;
    my $model = $self->model;
    my $data_directory = $model->data_directory;
    my $build_subdirectory = '/build'. $self->build_id;
    if ($data_directory =~ /\/gscmnt\/.*\/info\/(medseq\/)?(.*)/) {
        my $allocation_path = $2;
        $allocation_path .= $build_subdirectory;
        my $kb_requested = $self->calculate_estimated_kb_usage;
        if ($kb_requested) {
            my $disk_allocation = Genome::Disk::Allocation->allocate(
                                                                     disk_group_name => 'info_genome_models',
                                                                     allocation_path => $allocation_path,
                                                                     kilobytes_requested => $kb_requested,
                                                                     owner_class_name => $self->class,
                                                                     owner_id => $self->id,
                                                                 );
            unless ($disk_allocation) {
                $self->error_message('Failed to get disk allocation');
                $self->delete;
                die $self->error_message;
            }
            my $build_symlink = $data_directory . $build_subdirectory;
            unlink $build_symlink if -e $build_symlink;
            my $build_data_directory = $disk_allocation->absolute_path;
            unless (Genome::Utility::FileSystem->create_directory($build_data_directory)) {
                $self->error_message("Failed to create directory '$build_data_directory'");
                die $self->error_message;
            }
            unless (Genome::Utility::FileSystem->create_symlink($build_data_directory,$build_symlink)) {
                $self->error_message("Failed to make symlink '$build_symlink' with target '$build_data_directory'");
                die $self->error_message;
            }
            return $build_data_directory;
        }
    }
    return $data_directory . $build_subdirectory;
}

#< Reports >#
sub resolve_reports_directory
{
    my $self = shift;
    return  $self->data_directory . '/reports/';
}

sub add_report {
    my ($self, $report) = @_;

    my $directory = $self->resolve_reports_directory;
    if (-d $directory) {
        my $subdir = $directory . '/' . $report->name_to_subdirectory($report->name);
        if (-e $subdir) {
            $self->status_message("Sub-directory $subdir exists!   Moving it out of the way...");
            my $n = 1;
            my $max = 20;
            while ($n < $max and -e $subdir . '.' . $n) {
                $n++;
            }
            if ($n == $max) {
                die "Too many re-runs of this report!  Contact Informatics..."
            }
            rename $subdir, "$subdir.$n";
            if (-e $subdir) {
                die "failed to move old report dir $subdir to $subdir.$n!: $!";
            }
        }
    }
    else {
        $self->status_message("creating directory $directory...");
        unless (Genome::Utility::FileSystem->create_directory($directory)) {
            die "failed to make directory $directory!: $!";
        }
    }
    
    if ($report->save($directory)) {
        $self->status_message("Saved report to override directory: $directory");
        return 1;
    }
    else {
        $self->error_message("Error saving report!: " . $report->error_message());
        return;
    }
}

sub available_reports {
    my $self = shift;
    my $report_dir = $self->resolve_reports_directory;
    return unless -d $report_dir;
    return Genome::Report->create_reports_from_parent_directory($report_dir);
}

#< SUBCLASSING >#
#
# This is called by the infrastructure to appropriately classify abstract processing profiles
# according to their type name because of the "sub_classification_method_name" setting
# in the class definiton...
sub _resolve_subclass_name {
    my $class = shift;

    my $type_name;
	if ( ref($_[0]) and $_[0]->isa(__PACKAGE__) ) {
		$type_name = $_[0]->model->type_name;
	}
    else {
        my %params = @_;
        my $model_id = $params{model_id};
        my $model = Genome::Model->get($model_id);
        unless ($model) {
            return undef;
        }
        $type_name = $model->type_name;
    }

    unless ( $type_name ) {
        my $rule = $class->get_rule_for_params(@_);
        $type_name = $rule->specified_value_for_property_name('type_name');
    }

    if (defined $type_name ) {
        my $subclass_name = $class->_resolve_subclass_name_for_type_name($type_name);
        my $sub_classification_method_name = $class->get_class_object->sub_classification_method_name;
        if ( $sub_classification_method_name ) {
            if ( $subclass_name->can($sub_classification_method_name)
                 eq $class->can($sub_classification_method_name) ) {
                return $subclass_name;
            } else {
                return $subclass_name->$sub_classification_method_name(@_);
            }
        } else {
            return $subclass_name;
        }
    } else {
        return undef;
    }
}

sub _resolve_subclass_name_for_type_name {
    my ($class,$type_name) = @_;
    my @type_parts = split(' ',$type_name);

    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);

    my $class_name = join('::', 'Genome::Model::Build' , $subclass);
    return $class_name;

}

sub _resolve_type_name_for_class {
    my $class = shift;

    my ($subclass) = $class =~ /^Genome::Model::Build::([\w\d]+)$/;
    return unless $subclass;

    return lc join(" ", ($subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx));

    my @words = $subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx;
    return lc(join(" ", @words));
}

sub get_all_objects {
    my $self = shift;

    my @events = $self->events;
    if ($events[0] && $events[0]->id =~ /^\-/) {
        @events = sort {$a->id cmp $b->id} @events;
    } else {
        @events = sort {$b->id cmp $a->id} @events;
    }
    return @events;
}

sub yaml_string {
    my $self = shift;
    my $string = YAML::Dump($self);
    for my $object ($self->get_all_objects) {
        $string .= YAML::Dump($object);
    }
    return $string;
}

sub add_to_build{
    my $self = shift;
    my (%params) = @_;
    my $build = delete $params{to_build};
    my $role = delete $params{role};
    $role||='member';
   
    $self->error_message("no to_build provided!") and die unless $build;
    my $from_id = $self->id;
    my $to_id = $build->id;
    unless( $to_id and $from_id){
        $self->error_message ( "no value for this build(from_build) id: <$from_id> or to_build id: <$to_id>");
        die;
    }
    my $reverse_bridge = Genome::Model::Build::Link->get(from_build_id => $to_id, to_build_id => $from_id);
    if ($reverse_bridge){
        my $string =  "A build link already exists for these two builds, and in the opposite direction than you specified:\n";
        $string .= "to_build: ".$reverse_bridge->to_build." (this build)\n";
        $string .= "from_build: ".$reverse_bridge->from_build." (the build you are trying to set as a 'to' build for this one)\n";
        $string .= "role: ".$reverse_bridge->role;
        $self->error_message($string);
        die;
    }
    my $bridge = Genome::Model::Build::Link->get(from_build_id => $from_id, to_build_id => $to_id);
    if ($bridge){
        my $string =  "A build link already exists for these two builds:\n";
        $string .= "to_build: ".$bridge->to_build." (the build you are trying to set as a 'to' build for this one)\n";
        $string .= "from_build: ".$bridge->from_build." (this build)\n";
        $string .= "role: ".$bridge->role;
        $self->error_message($string);
        die;
    }
    $bridge = Genome::Model::Build::Link->create(from_build_id => $from_id, to_build_id => $to_id, role => $role);
    return $bridge;
}

sub add_from_build{
    my $self = shift;
    my (%params) = @_;
    my $build = delete $params{from_build};
    my $role = delete $params{role};
    $role||='member';
   
    $self->error_message("no from_build provided!") and die unless $build;
    my $to_id = $self->id;
    my $from_id = $build->id;
    unless( $to_id and $from_id){
        $self->error_message ( "no value for this build(to_build) id: <$to_id> or from_build id: <$from_id>");
        die;
    }
    my $reverse_bridge = Genome::Model::Build::Link->get(from_build_id => $to_id, to_build_id => $from_id);
    if ($reverse_bridge){
        my $string =  "A build link already exists for these two builds, and in the opposite direction than you specified:\n";
        $string .= "to_build: ".$reverse_bridge->to_build." (the build you are trying to set as a 'from' build for this one)\n";
        $string .= "from_build: ".$reverse_bridge->from_build." (this build)\n";
        $string .= "role: ".$reverse_bridge->role;
        $self->error_message($string);
        die;
    }
    my $bridge = Genome::Model::Build::Link->get(from_build_id => $from_id, to_build_id => $to_id);
    if ($bridge){
        my $string =  "A build link already exists for these two builds:\n";
        $string .= "to_build: ".$bridge->to_build." (this build)\n";
        $string .= "from_build: ".$bridge->from_build." (the build you are trying to set as a 'from' build for this one)\n";
        $string .= "role: ".$bridge->role;
        $self->error_message($string);
        die;
    }
    $bridge = Genome::Model::Build::Link->create(from_build_id => $from_id, to_build_id => $to_id, role => $role);
    return $bridge;
}



sub delete {
    my $self = shift;

    my @objects = $self->get_all_objects;
    for my $object (@objects) {
        $object->delete;
    }
    #idas = instrument data assignments
    my @idas = $self->instrument_data_assignments;
    for my $ida (@idas) {
        $ida->first_build_id(undef);
    }
    if ($self->data_directory && -e $self->data_directory) {
        unless (rmtree $self->data_directory) {
            $self->warning_message('Failed to rmtree build data directory '. $self->data_directory);
        }
    }
    my $disk_allocation = $self->disk_allocation;
    if ($disk_allocation) {
        my $allocator_id = $disk_allocation->allocator_id;
        my $deallocate_cmd = Genome::Disk::Allocation::Command::Deallocate->create(allocator_id =>$allocator_id);
        unless ($deallocate_cmd) {
            $self->warning_message('Failed to create a deallocate command.');
        }
        unless ($deallocate_cmd->execute) {
            $self->warning_message('Failed to deallocate disk space.');
        }
    }
    return $self->SUPER::delete;
}


package Genome::Model::Build::AbstractBaseTest;

class Genome::Model::Build::AbstractBaseTest {
    is => 'Genome::Model::Build',
};

1;

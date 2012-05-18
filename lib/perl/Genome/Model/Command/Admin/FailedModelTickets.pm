package Genome::Model::Command::Admin::FailedModelTickets;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
use Error qw(:try);
use File::Find 'find';
use File::Grep 'fgrep';
require IO::Prompt;
require RT::Client::REST;
require RT::Client::REST::Ticket;
require WWW::Mechanize;

class Genome::Model::Command::Admin::FailedModelTickets {
    is => 'Command::V2',
    doc => 'find failed cron models, check that they are in a ticket',
    has_input => [
        include_failed => {
            is => 'Boolean',
            default_value => 1,
            doc => 'Include builds with status Failed',
        },
        include_unstartable => {
            is => 'Boolean',
            default_value => 1,
            doc => 'Include builds with status Unstartable',
        },
		ignore_pending_rerun => {
			is => 'Boolean',
			default_value => 0,
			doc => 'Ignore builds which are followed by a later build that is scheduled or running.'
		}
    ],
};

sub help_detail {
    return <<HELP;
This command collects cron models by failed or unstartable build events and scours tickets for them. If they are not found, the models are summaraized first by the error entry log and then by grepping the error log files. The summary is the printed to STDOUT.
HELP
}

sub execute {
    my $self = shift;

    # Connect
    my $rt = _login_sso();
    $rt = _login_direct() if not $rt;

    # Retrieve tickets - 
    $self->status_message('Looking for tickets...');
    my @ticket_ids;
    try {
        @ticket_ids = $rt->search(
            type => 'ticket',
            query => "Queue = 'apipe-builds' AND ( Status = 'new' OR Status = 'open' )",

        );
    }
    catch Exception::Class::Base with {
        my $msg = shift;
        if ( $msg eq 'Internal Server Error' ) {
            die 'Incorrect username or password';
        }
        else {
            die $msg->message;
        }
    };
    $self->status_message('Found '.@ticket_ids.' tickets');

    # Find cron models by failed build events
    my @events;
    if ($self->include_failed) {
        $self->status_message('Looking for failed models...');
        @events = Genome::Model::Event->get(
            event_status => 'Failed',
            event_type => 'genome model build',
            user_name => 'apipe-builder',
            -hint => [qw/ build /],
        );
    }
    # Find cron models by unstartable build events
    my @unstartable_events;
    if ($self->include_unstartable) {
        $self->status_message('Looking for unstartable models...');
        @unstartable_events = Genome::Model::Event->get(
            event_status => 'Unstartable',
            event_type => 'genome model build',
            user_name => 'apipe-builder',
            -hint => [qw/ build /],
        );
    }
    if ( (not $self->include_unstartable or not @unstartable_events) and 
         (not $self->include_failed or not @events) ) {
        $self->status_message('No failed or unstartable build events found!');
        return 1;
    }
    my %models_and_builds;
    for my $event ( @events, @unstartable_events ) {
        next if not $event->build_id;
        my $build = Genome::Model::Build->get(id => $event->build_id, -hint => [qw/ model events /]);
        my $model = $build->model;
        #If the latest build of the model succeeds, ignore those old
        #failing ones that will be cleaned by admin "cleanup-succeeded".
        next if $model->status eq 'Succeeded';
		
		if ($self->ignore_pending_rerun) {
			next if $model->status eq 'Scheduled';
			next if $model->status eq 'Running';
		}
		
        next if $models_and_builds{ $model->id } and $models_and_builds{ $model->id }->id > $build->id;
        $models_and_builds{ $model->id } = $build;
    }
    $self->status_message('Found '.keys(%models_and_builds).' models');

    # Go through tickets
    my %tickets;
    $self->status_message('Matching failed models and tickets...');
    for my $ticket_id ( @ticket_ids ) {
        my $ticket = RT::Client::REST::Ticket->new(
            rt => $rt,
            id => $ticket_id,
        )->retrieve;
        my $transactions = $ticket->transactions;
        my $transaction_iterator = $transactions->get_iterator;
        while ( my $transaction = &$transaction_iterator ) {
            my $content = $transaction->content;
            for my $model_id ( keys %models_and_builds ) {
                my $build_id = $models_and_builds{$model_id}->id;
                next if $content !~ /$model_id/ and $content !~ /$build_id/;
                delete $models_and_builds{$model_id};
                push @{$tickets{$ticket_id.' '.$ticket->subject}}, $model_id;
            }
        }
    }

    # Consolidate errors
    $self->status_message('Consolidating errors...');
    my %build_errors;
    my %guessed_errors;
    my $models_with_errors = 0;
    my $models_with_guessed_errors = 0;
    for my $build ( values %models_and_builds ) {
        my $key = 'Unknown';
        my $msg = 'Failure undetermined!';
        my $error = $self->_pick_optimal_error_log($build);
        if ( $error
                and
            ( ($error->file and $error->line) or ($error->inferred_file and $error->inferred_line) )
                and
            ($error->message or $error->inferred_message)
        ) {
            if ( $error->file and $error->line ) {
                $key = $error->file.' '.$error->line;
            } elsif ( $error->inferred_file and $error->inferred_line ) {
                $key = $error->inferred_file.' '.$error->inferred_line;
            } else {
                $key = 'unknown';
            }

            if ( $error->message ) {
                $msg = $error->message;
            } elsif ( $error->inferred_message ) {
                $msg = $error->inferred_message;
            } else {
                $msg = 'unknown';
            }

            $models_with_errors++;
        }
        elsif ( my $guessed_error = $self->_guess_build_error($build) ) {
            if ( not $guessed_errors{$guessed_error} ) {
                $guessed_errors{$guessed_error} = scalar(keys %guessed_errors) + 1;
            }
            $key = "Unknown, best guess #".$guessed_errors{$guessed_error};
            $msg = $guessed_error;
            $models_with_guessed_errors++;
        }
        $build_errors{$key} = "File:\n$key\nExample error:\n$msg\nModel\t\tBuild\t\tType/Failed Stage:\n" if not $build_errors{$key};
        my $type_name = $build->type_name;
        $type_name =~ s/\s+/\-/g;
        my %failed_events = map { $_->event_type => 1 } grep { $_->event_type ne 'genome model build' } $build->events('event_status in' => [qw/ Crashed Failed /]);
        my $failed_event = (keys(%failed_events))[0] || '';
        $failed_event =~ s/genome model build $type_name //;
        if ($failed_event eq '') {
            if ($build->status eq 'Unstartable') {
                $failed_event = 'Unstartable';
            }
        }
        $build_errors{$key} .= join("\t", $build->model_id, $build->id, $type_name.' '.$failed_event)."\n";
    }

    # Report
    my $models_in_tickets = map { @{$tickets{$_}} }keys %tickets;
    my $models_not_in_tickets = keys %models_and_builds;
    $self->status_message('Models: '.($models_in_tickets+ $models_not_in_tickets));
    $self->status_message('Models in tickets: '.$models_in_tickets);
    $self->status_message('Models not in tickets: '.$models_not_in_tickets);
    $self->status_message('Models with error log: '.$models_with_errors);
    $self->status_message('Models with guessed errors: '.$models_with_guessed_errors);
    $self->status_message('Models with unknown failures: '.($models_not_in_tickets - $models_with_errors - $models_with_guessed_errors));
    $self->status_message('Summarized errors: ');
    $self->status_message(join("\n", map { $build_errors{$_} } sort keys %build_errors));

    return 1;
}

sub _server {
    #return 'https://rt.gsc.wustl.edu/';
    return 'https://rt-dev.gsc.wustl.edu/';
}

sub _get_pw {
    my ($msg) = @_;
    #my ($self, $msg) = @_;
    my $pw = IO::Prompt::prompt($msg, -e => "*");
    if ( $pw->{value} eq '' ) {
        die 'No password entered! Exiting!';
    }
    return $pw->{value};
}

sub _login_sso {
    my $self = shift;

    my $mech = WWW::Mechanize->new(
        after =>  1,
        timeout => 10,
        agent =>  'WWW-Mechanize',
    );
    $mech->get( _server() );

    my $uri = $mech->uri;
    my $host = $uri->host;
    if ($host ne 'sso.gsc.wustl.edu') {
        return;
    }

    $mech->submit_form (
        form_number =>  1,
        fields =>  {
            j_username => Genome::Sys->username,
            j_password => _get_pw('SSO Password: '),
        },
    );
    $mech->submit();

    return RT::Client::REST->new(server => _server(), _cookie =>  $mech->{cookie_jar});
}

sub _login_direct { 
    my $self = shift;

    local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    my $cookie_file = $ENV{HOME}."/.rt_cookie";
    my $cookie_jar = HTTP::Cookies->new(file => $cookie_file);
    my $rt = RT::Client::REST->new(server => _server(), _cookie => $cookie_jar);
    try {
        $rt->login(
            username => Genome::Sys->username,
            password => _get_pw('Ticket Tracker Password: '),
        );
    } catch Exception::Class::Base with {
        my $msg = shift;
        die $msg->message;
    };
    $rt->_cookie->{ignore_discard} = 1;
    $rt->_cookie->save($cookie_file);

    return $rt;
}

sub _guess_build_error {
    my ($self, $build) = @_;

    if ($build->status eq 'Unstartable') {
        return $self->_guess_build_error_from_notes($build);
    }
    else {
        return $self->_guess_build_error_from_logs($build);
    }
}

sub _guess_build_error_from_notes {
    my ($self, $build) = @_;

    my $error = "Unstartable unknown error";
    my @notes = $build->notes;
    if (not @notes) {
        return $error;
    }
    my @unstartable_notes = grep {$_->header_text eq 'Unstartable'} @notes;
    if (not @unstartable_notes) {
        return $error;
    }
    my $note = $unstartable_notes[0];

    my $text = $note->body_text;
    if (not $text) {
        return $error;
    }

    my @lines = split(/\n/, $text);

    @lines = grep (/ERROR:\s+/, @lines);

    my $line_count = scalar @lines;
    if ($line_count == 0) {
        return $error;
    }

    my %errors;
    foreach my $line (@lines) {
        my ($err) = (split(/ERROR:\s+/, $line))[1];
        chomp $err;
        $errors{$err} = 1; 
    }
    return join("\n", sort keys %errors);
}

sub _guess_build_error_from_logs {
    my ($self, $build) = @_;

    my $data_directory = $build->data_directory;
    my $log_directory = $data_directory.'/logs';
    return unless -d $log_directory;
    my %errors;
    find(
        sub{
            return unless $_ =~ /\.err$/;
            my @grep = (fgrep { /ERROR:\s+/ } $_ );
            return if $grep[0]->{count} == 0;
            for my $line ( values %{$grep[0]->{matches}} ) {
                my ($err) = (split(/ERROR:\s+/, $line))[1];
                chomp $err;
                next if $err eq "Can't convert workflow errors to build errors";
                next if $err eq 'relation "error_log_entry" does not exist';
                next if $err =~ /current transaction is aborted/;
                next if $err =~ /run_workflow_ls/;
                $errors{$err} = 1;
            }
        },
        $log_directory,
    );

    return join("\n", sort keys %errors);
}

sub _pick_optimal_error_log{
    my $self = shift;
    my $build = shift;
    my @errors = Genome::Model::Build::ErrorLogEntry->get(build_id => $build->id);
    my @optimal_errors = grep($_->file, @errors);
    unless (@optimal_errors){
        @optimal_errors = grep($_->inferred_file, @errors);
    }
    unless(@optimal_errors){
        return 0;
    }
    return shift @optimal_errors;
}
1;

package Genome::Sys::Command::Search::PurgeOrphans;

use strict;
use warnings;

use Genome;
use WebService::Solr;

class Genome::Sys::Command::Search::PurgeOrphans {
    is => 'Command::V2',
    doc => 'Remove documents from search index which no longer have corresponding objects in the database.',
    has => [
        start => {
            is => 'Number',
            default => 0,
            doc => 'Starting row index.',
        },
        rows => {
            is => 'Number',
            default => 2_500_000,
            doc => 'Number of rows to request.',
        },
        batch_size => {
            is => 'Number',
            default => 5_000,
            doc => 'Number of documents to process per batch.',
        },
    ],
};

sub help_detail {
    'Scans the Search engine index for documents which no longer have corresponding objects in the database and removes them.';
}

sub execute {
    my $self = shift;

    $self->status_message('This takes a couple hours...');

    my $start_time = time;
    my $response = Genome::Search->search(
        'id:[* TO *]',
        {
            start => $self->start,
            rows => $self->rows,
            fl => 'id,object_id,class',
            hl => 'false',
            defType => 'lucene',
        },
    );
    unless($response->ok) {
        $self->error_message("Search response failed, aborting.");
        exit;
    }

    my @all_docs = $response->docs;
    print("Got " . @all_docs . " objects from Solr in " . (time - $start_time) . " seconds.\n");

    while (@all_docs) {
        # loops over batches of documents
        # forks a child process to handle each batch so memory is limited and freed
        my @docs;
        while (@docs < $self->batch_size && @all_docs) {
            push @docs, shift @all_docs;
        }

        my $pid = fork();
        if (not defined $pid) {
            die "Failed to fork";
        }
        elsif ($pid == 0) {
            # CHILD
            $start_time = time;

            # batch by class
            my %docs;
            for my $doc (@docs) {
                my $class = $doc->value_for('class');

                # filter "transient" classes
                next if $class =~ /^Genome::Sys::Email/;
                next if $class =~ /^Genome::Wiki::Document/;

                push @{$docs{$class}}, $doc;
            }

            # find orphaned documents
            my @docs_to_purge;
            for my $class (keys %docs) {
                my @docs = @{$docs{$class}};
                if ($class->can('get')) {
                    my @object_ids_from_solr = map { $_->value_for('object_id') } @docs;
                    my @objects = $class->get(\@object_ids_from_solr);
                    for my $doc (@docs) {
                        my $id_from_solr = $doc->value_for('object_id');
                        unless (grep { $id_from_solr eq $_->id } @objects) {
                            push @docs_to_purge, $doc;
                        }
                    }
                } else {
                    @docs_to_purge = @docs;
                }
            }
            print("Processed " . @docs . " search documents in " . (time - $start_time) . " seconds and found " . @docs_to_purge . " to remove.\n");

            if (@docs_to_purge) {
                $start_time = time;
                my $response = Genome::Search->delete_by_doc(@docs_to_purge);
                if ($response->ok) {
                    print("Removed those " . @docs_to_purge . "documents in " . (time - $start_time) . " seconds.\n");
                } else {
                    print("Failed to remove those " . @docs_to_purge . " documents.\n");
                }
            }

            exit;
        }
        else {
            # PARENT
            waitpid($pid, 0);
        }
    }
    return 1;
}

1;

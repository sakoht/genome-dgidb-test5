#:boberkfe i think this should be dumped?

package Genome::Model::ReferenceAlignment::Report::MetricSummary;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use IO::File;

class Genome::Model::ReferenceAlignment::Report::MetricSummary { 
    is => 'Genome::Model::Command',
    has => [ 
        exclude_chromosomes => {
            is => 'Text',
            is_optional => 1,
            doc => 'comma-separated list of chromosomes to exclude from metrics'
        }
    ],
};

sub execute {
    my $self = shift;
    my $model_id = $self->model_id;

    my $dbh = Genome::DataSource::GMSchema->get_default_dbh();
    
    my $ref_seq_exclusion;
    if (my $exclude = $self->exclude_chromosomes) {
        my @exclude = split(",",$exclude);
        $ref_seq_exclusion = ' and ref_seq_id not in (' . join(",",map { "'$_'"  } @exclude) . ')';     
    }

    print "Stage 1: Run/Lane-Centric Metrics\n"; 
    my $sql_stage1 = qq|
        select v.metric_name,e.event_type,count(distinct r.run_name) run_count,count(distinct e.run_id) lane_count,to_char(to_number(sum(metric_value)),'999,999,999,999,999,999') 
        from mg.genome_Model_event e 
        join mg.genome_model_run r on r.seq_id = e.run_id
        join mg.genome_Model_event_metric v on v.event_id = e.genome_model_event_id 
        where e.model_id = $model_id
        and e.ref_seq_id is null  
        group by (v.metric_name,e.event_type) 
        order by sum(metric_value) desc
    |;
    IO::File->new("| sqlrun --instance warehouse - --nocount")->print($sql_stage1);
        
    print "\nStage 2: Consensus Metrics\n"; 
    my $sql_stage2 = qq|
        select v.metric_name,e.event_type,count(distinct e.ref_seq_id),to_char(to_number(sum(metric_value)),'999,999,999,999,999,999') sum
        from mg.genome_Model_event e 
            join mg.genome_Model_event_metric v on v.event_id = e.genome_model_event_id 
        where e.model_id = $model_id
            and e.run_id is null  
            $ref_seq_exclusion 
        group by v.metric_name,e.event_type 
        order by sum(metric_value) desc,event_type,metric_name
    |;
    IO::File->new("| sqlrun --instance warehouse - --nocount")->print($sql_stage2);
    
    return 1;
}

1;

#$HeadURL$
#$Id$

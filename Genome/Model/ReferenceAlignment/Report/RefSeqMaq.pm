package Genome::Model::ReferenceAlignment::Report::RefSeqMaq;

use strict;
use warnings;

use Genome;

use CGI;
use IO::String;
use App::Report;


class Genome::Model::ReferenceAlignment::Report::RefSeqMaq {
    is => 'Genome::Model::Report',
    has =>
    [
        #if we have a ref seq, just get that, otherwise get 'em all
        ref_seq_name => {is => 'VARCHAR2', len => 64, is_optional => 1, doc => 'Identifies Ref Sequence'},
        bfa_path =>
        {
            type => 'String',
            doc => "Path for .bfa file", #does this need to be a param?
            #default => "/gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/",
            default => "/gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/",
        }, 
        accumulated_alignments_file =>
        {
            type => 'String',
            doc => "Accumulated alignments file name i.e. the big map file",
            is_optional => 1,
        },
        version   => { 
            is => 'String', 
            default =>'maq0_6_8', 
            doc =>"vmerge for 'maq0_6_8' or 'maq0_7_1'",
        },

        cmd =>
        {
            type => 'String',
            doc => "system command for generating report", #does this need to be a param?
            default => "/gsc/pkg/bio/maq/maq-0.6.8_x86_64-linux/maq mapcheck",
        },
    ],
};


sub default_format {
    'html'
}

sub available_formats {
    return ('html')
}

sub _generate_data {
    my $self = shift;

    return {
        description => $self->generate_report_brief,
        html => $self->generate_report_detail,
    };
}

sub generate_report_brief 
{
    my $self=shift;
   
    my $model = $self->model;
    #my $output_file =  $self->report_brief_output_filename;
    
    #my $brief = IO::File->new(">$output_file");
    #die unless $brief;

    #my $desc = "maq mapcheck coverage for " . $model->name . " as of " . UR::Time->now;
    #$brief->print("<div>$desc</div>");
    #$brief->close;
    
    return '<div>maq mapcheck coverage for ' . $model->name . " as of " . UR::Time->now.'</div>';
}

sub generate_report_detail 
{
    my $self = shift;
    #$self->get_maq_content;
    #return;
    return $self->get_maq_content;
}

sub get_maq_content
{
    my $self = shift;
    my $model = $self->model;

    my ($maq_file, $bfa_file, $cmd, @maq, $fh, $file_name, %output, $rpt,$maplist);
    
    my $reports_dir = $self->build->resolve_reports_directory;
    #my $reports_dir = $self->model->resolve_reports_directory;
    #$file_name = $self->report_detail_output_filename;
    #$self->status_message("Will write final report file to: ".$file_name);
 
    my $result_file = $self->accumulated_alignments_file;

    #my $result_file; 
    #if ($model->id < 10 ) {
    #	   $result_file = $self->accumulated_alignments_file; 
    #} else {
    #   #moved to EventWithRefSeq	
    #} 

    #$bfa_file = $self->bfa_path . "22" . ".bfa " . $result_file;
    $bfa_file = $self->bfa_path . "all_sequences.bfa " . $result_file;
    if ($self->version eq 'maq0_6_8') {
        $cmd = '/gsc/pkg/bio/maq/maq-0.6.8_x86_64-linux/maq';
    } elsif ($self->version eq 'maq0_7_1') {
        $cmd = '/gsc/pkg/bio/maq/maq-0.7.1-64/bin/maq';
    }
    else {
        die "wtf?";
    }    
 
    $cmd .=  " mapcheck $bfa_file"; 
    $self->status_message("Mapcheck command: ".$cmd);
    @maq = `$cmd`;
    $rpt = join('',@maq);
    $rpt = $self->format_maq_content($rpt); 
    
    #make detail report
    #$file_name = $self->report_detail_output_filename;
    #$self->warning_message("Writing final report to: ".$file_name);
    #$fh = IO::File->new(">$file_name");        
    $fh = IO::String->new();        
    $fh->print($rpt);
    #$fh->close;

    $fh->seek(0 ,0);
    return join('', $fh->getlines);
}

sub get_ref_seq_iterator
{
    my $self = shift;
    my $i;
    if ($self->ref_seq_name)
    {
        $i = Genome::Model::RefSeq->create_iterator(where => [ model_id=> $self->model_id,
                                                               ref_seq_name => $self->ref_seq_name,
                                                               variation_position_read_depths => 2 ]);
    }
    else
    {
        $i = Genome::Model::RefSeq->create_iterator(where => [ model_id=> $self->model_id,
                                                                  variation_position_read_depths => 2 ]);
    }
    return $i;
} 

sub get_coverage_filename
{
    my $self = shift;
    my $reports_dir = $self->build->resolve_reports_directory;
    #my $reports_dir = $self->model->resolve_reports_directory;
    my $model = $self->model;
    return $reports_dir . '/' .  $model->genome_model_id . '_coverage_detail.html';
}
sub format_maq_report
{
    #format plain text for html viewability
    my ($self,$content) = @_;

    my ($stats, $table);
    if ($content=~m/(.*)(\n\n)(.*)/sm)
    {
        ($stats, $table) = ($1, $3); 
        $stats=~s/\n/\<br>\n/g; 
        $stats = "<div id=\"stats\">$stats</div>";
    
        my @table = split("\n",$table);
        for (my $row = 0, my $cell, my $formatted_cell = ''; $row < scalar(@table); $row++, $formatted_cell = '')
        {   
            $cell = $table[$row];
            #trim leading & trailing
            $cell=~ s/^\s+//;
	    $cell=~ s/\s+$//;
    
            #wrap cells
            if ($row == 0) #header
            {
                $cell=~s/\s*:\s/ /g;
                $cell=~s/\s+/<\/th><th>/g;
                $formatted_cell="<tr><td id=\"corner\"></td><th>$cell</th></tr>";
            
            }
            else
            {
                #color-code colon-delimited sections
                if ($cell=~m/(\s*)(\d+)(\s*)(.*?)(\s*:\s*)(.*?)(\s*:\s*)(.*?)(\s*:\s*)(.*)/)
                {
                    my (@sections) = ($2, $4, $6, $8, $10);
                    for (my $i = 0, my $sec; $i < scalar(@sections); $i++)
                    {
                        $sec = $sections[$i];
                        $sec=~s/\s+/<\/td><td class=\"sec$i\">/g;
                        $sec = "<td class=\"sec$i\">$sec</td>";
                        $formatted_cell .= $sec;
                    }
                
                }
                $formatted_cell = "<tr>$formatted_cell</tr>";
            } 
            $table[$row] = $formatted_cell;
        }
   
        $table = join('',@table);
        $table = "\n<table border=1 id=\"data\">$table</table>";

        return "<!--\n$content\n-->\n" . 
               "<div id=\"maq_report\">" .
               $stats . 
               $table . 
               "</div>" .   
               $self->get_style;
    }
    else
    {
        die("Expected format STATS \n\n TABLE");
    }
}

sub format_maq_content
{
    my ($self,$content) = @_;

    my ($stats, $table, @table);

    if ($content=~m/(.*)(\n\n)(.*)/sm)
    {
        ($stats, $table) = ($1, $3); 
        $stats=~s/\n/\<br>\n/g; 
        $stats = "<div id=\"stats\">$stats</div>";
    
        @table = split("\n",$table);
        for (my $row = 0, my $cell, my $formatted_cell = ''; $row < scalar(@table); $row++, $formatted_cell = '')
        {   
            $cell = $table[$row];
            #trim leading & trailing
            $cell=~ s/^\s+//;
            $cell=~ s/\s+$//;
    
            #wrap cells
            if ($row == 0) #header
            {
                $cell=~s/\s*:\s/ /g;
                $cell=~s/\s+/<\/th><th>/g;
                $formatted_cell="<tr><td id=\"corner\"></td><th>$cell</th></tr>";
            
            }
            else
            {
                #color-code colon-delimited sections
                if ($cell=~m/(\s*)(\d+)(\s*)(.*?)(\s*:\s*)(.*?)(\s*:\s*)(.*?)(\s*:\s*)(.*)/)
                {
                    my (@sections) = ($2, $4, $6, $8, $10);
                    for (my $i = 0, my $sec; $i < scalar(@sections); $i++)
                    {
                        $sec = $sections[$i];
                        $sec=~s/\s+/<\/td><td class=\"sec$i\">/g;
                        $sec = "<td class=\"sec$i\">$sec</td>";
                        $formatted_cell .= $sec;
                    }

                    $formatted_cell = "<tr>$formatted_cell</tr>";
                }
            } 
        
            $table[$row] = $formatted_cell;
        }
    }
    $table = join('',@table);
    $table = "\n<table border=1 id=\"data\">$table</table>";

    return "<!--\n$content\n-->\n" . 
           "<div id=\"maq_report\">" .
           $stats .
           $table . 
           "</div>" . 
           $self->get_css;
}

sub get_css
{    
    return
"    <style>

    #maq_report #data #corner
    {
        border-bottom: 2px solid #6699CC;
        border-right: 1px solid #6699CC;
        border-top, border-left:#000000;
        background-color: #BEC8D1;
    }

    th
    { border-bottom: 2px solid #6699CC;
    border-left: 1px solid #6699CC;
    background-color: #BEC8D1;
    text-align: center;
    font-family: Verdana;
    font-weight: bold;
    font-size: 16px;
    color: #404040; }

 td
    { border-bottom: 1px solid #000;
    border-top: 0px;
    border-left: 1px solid #000;
    border-right: 0px;
    font-family: Verdana, sans-serif, Arial;
    font-weight: normal;
    font-size: 14px;
    padding: 0 0 0 0;
    
    background-color: #fafafa;
    border-spacing: 0px;
    margin-top: 0px;
}


table
{
    text-align: center;
    font-family: Verdana;
    font-weight: normal;
    font-size: 14px;
    color: #404040;
    background-color: #fafafa;
    border: 1px #000 solid;
    border-collapse: collapse;
    border-spacing: 0px;
}

tr td{
    background-color: #fafafa;
}

tr.row0 td{
    background-color: #fafafa;
}

tr.row1 td{
    background-color: #eeeeee;
}
a img {
    border: medium none;
    border-collapse: collapse;
}
.drag_it {
}
.sec0
    { border-bottom: 2px solid #6699CC;
    border-right: 1px solid #6699CC;
    background-color: #BEC8D1;
    text-align: center;
    font-family: Verdana;
    font-weight: bold;
    font-size: 16px;
    color: #404040; }
.sec1
{
    background-color:#CCFFFF;
}
.sec2
{
    background-color:#FFFF99;
}
.sec3
{
    background-color:#FF9999;
}
.sec4
{
    background-color:#CCFFCC;
}

</style>";
}
1;

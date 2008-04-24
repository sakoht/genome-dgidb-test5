#!/gsc/bin/perl

use strict;
use warnings;

use FileHandle;
use MPSampleData::DBI;
use MPSampleData::RggInfo;
use Devel::Size qw/ size total_size /;

#read in dump file
#grab rgg_id
#query_db and get the quality values
#write out the result

#change to database
#MPSampleData::DBI->set_sql(change_db => qq{use sample_data});
#MPSampleData::DBI->sql_change_db->execute;
MPSampleData::DBI::myinit("dbi:Oracle:dwrac","mguser_prd");

MPSampleData::RggInfo->columns(Essential => qw{ rgg_id info_type info_value });

my $file = shift; #really crummy way to get the file name
my $handle = new FileHandle;
$handle->open($file, "r") or die "Couldn't open dump file\n";

my $quality_for = build_qual_hash($handle);


my $end_file = shift;
my $ef_file = new FileHandle;
$ef_file->open("$end_file","r") or die "Couldn't open annotation file\n";
my $header_line = $ef_file->getline; #ignore header
chomp($header_line);
my $output_handle = new FileHandle;
$output_handle->open("$end_file.quals","w") or die "Couldn't open output file\n";

#print new header
my @header = split q{,}, $header_line;
push @header, q{"SNP q-value"};
print $output_handle join(q{,}, @header), "\n";
my $append_line;
while($append_line = $ef_file->getline) {
    chomp $append_line;
    my (  $dbsnp,
          $gene,
          $chromosome,
          $start,
          $end,
          $al2,
          $al2_read_hg,
          $al2_read_cDNA,
          $al2_read_skin_dna,
          $al2_read_unique_dna_start,
          $al2_read_unique_dna_context,
          $al2_read_unique_cDNA_start,
          $al2_read_unique_cDNA_context,
          $al2_read_unique_skin_start,
          $al2_read_unique_skin_context,
          $al2_read_relapse_cDNA,
          $al1,
          $al1_read_hg,
          $al1_read_cDNA,
          $al1_read_skin_dna,
          $al1_read_unique_dna_start,
          $al1_read_unique_dna_context,
          $al1_read_unique_cDNA_start,
          $al1_read_unique_cDNA_context,
          $al1_read_unique_skin_start,
          $al1_read_unique_skin_context,
          $al1_read_relapse_cDNA,
          $gene_exp,
          $gene_det,
          $transcript,
          $strand,
          $trv_type,
          $c_position,
          $pro_str,
          $pph_prediction,
          $submit,
       ) = split ",", $append_line;
   my $real_qscore; 
    if( exists($quality_for->{$chromosome}{$start}{$end})) {
        $real_qscore =$quality_for->{$chromosome}{$start}{$end} ;
    }
    else {
        warn "SNP not found\n";
        $real_qscore = "NULL";
    }
    my @fields = (   $dbsnp,
        $gene,
        $chromosome,
        $start,
        $end,
        $al2,
        $al2_read_hg,
        $al2_read_cDNA,
        $al2_read_skin_dna,
        $al2_read_unique_dna_start,
        $al2_read_unique_dna_context,
        $al2_read_unique_cDNA_start,
        $al2_read_unique_cDNA_context,
        $al2_read_unique_skin_start,
        $al2_read_unique_skin_context,
        $al2_read_relapse_cDNA,
        $al1,
        $al1_read_hg,
        $al1_read_cDNA,
        $al1_read_skin_dna,
        $al1_read_unique_dna_start,
        $al1_read_unique_dna_context,
        $al1_read_unique_cDNA_start,
        $al1_read_unique_cDNA_context,
        $al1_read_unique_skin_start,
        $al1_read_unique_skin_context,
        $al1_read_relapse_cDNA,
        $gene_exp,
        $gene_det,
        $transcript,
        $strand,
        $trv_type,
        $c_position,
        $pro_str,
        $pph_prediction,
        $submit,
        $real_qscore,

    );
    print $output_handle join(q{,},@fields), "\n";    
    $output_handle->flush;
}
sub retrieve_rgg_id {
    my ($line) = @_;
    chomp($line);
    my ($chromosome,$start,$end,$allele1,$allele2,$allele1_type,$allele2_type,$num_reads1,$num_reads2,$rgg_id) = split "\t", $line;
    return $rgg_id;
}

sub build_qual_hash {
    my ($fh) = @_;
    my %return_hash;
    while(    my $line = $fh->getline) {
        chomp($line);
        my
        ($chromosome,$start,$end,$allele1,$allele2,$allele1_type,$allele2_type,$num_reads1,$num_reads2,$rgg_id) = split "\t", $line;
        my @quality_score = MPSampleData::RggInfo->search(rgg_id => $rgg_id,
            info_type => 'confidence',
        );
        my $real_qscore; 
        unless(scalar(@quality_score) == 1 && defined($quality_score[0])) {
            warn "Unable to find a single quality score for rgg_id: $rgg_id.\n";
            next;
        }

        if(!defined($quality_score[0]->info_value()) ) {
            $real_qscore = "NULL";
        }
        elsif($quality_score[0]->info_value() =~ /^.* reads .*/xs) {
            $real_qscore = "NULL";
        }
        else {
            $real_qscore = $quality_score[0]->info_value;
        }
        $return_hash{$chromosome}{$start}{$end} = $real_qscore;
    }
    print "qual hash size ", total_size(\%return_hash), "\n";
    return \%return_hash;
}

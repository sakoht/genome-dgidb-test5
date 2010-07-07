package Genome::Model::Tools::Velvet::ToAce;

use strict;
use warnings;

use DBI;
use Genome;
use Bio::SeqIO;
use File::Temp;
use Date::Format;
use AMOS::AmosLib;
use File::Basename;
require File::Temp;

use GSC::IO::Assembly::Ace::Writer;

use Data::Dumper;

#Notes from Feiyu (Mar 2009):
#velvet 7.30 change RED id naming for iid(internal) and eid(external): eid = iid + 1, so iid is 0-based and eid is 1-based.
#Sequences file lists reads 0-based.
#Pcap names scaffold 0-based, while contig 1-based.
#Original velvet_asm.afg file names scaffold 1-based, while it names contig 0-based. This tool will convert to pcap scaffold/contig naming
#In afg file's TLE field, src lists read's iid(0-based) not eid(1-based).
#contigs.fa is actually supercontig/scaffold fasta for recent velvet version so it is 1-based.

#velvet 7.44 RED id naming: iid = eid and is 1-based. TLE field src points to RED iid/eid (now same). Sequences file generated by 
#velveth now is using the real read name instead of silly index id.


class Genome::Model::Tools::Velvet::ToAce {
    is           => 'Command',
    has          => [
        afg_file    => {
            is      => 'String', 
            doc     => 'input velvet_asm.afg file path',
        }
    ],
    has_optional => [
        out_acefile => {
            is      => 'String', 
            doc     => 'name for output acefile, default is ./velvet_asm.ace',
            default => 'velvet_asm.ace',
        },
        seq_file    => {
            is      => 'String', 
            doc     => 'path name for Sequences file generated by velveth. Actual read names (not index id) will be used in acefile with this index. Default is to use Sequences file in the same directory as afg_file. Do not use this option unless you are very sure',
        },
        time        => {
            is      => 'String',
            doc     => 'timestamp inside acefile, must be sync with phd timestamp',
        },
        sqlite_yes  => {
            is      => 'Boolean',
            doc     => 'Use sqlite database to store read id, names, position. This is to save memory but will be VERY slow. Use this option only if get more than 9 million reads to assemble',
        },

    ],
};
        

sub help_brief {
    "This tool converts velvet output velvet_asm.afg into acefile format",
}


sub help_synopsis {
    return <<"EOS"
gmt velvet to-ace --afg-file velvet_asm.afg [--out-acefile acefile_name]
EOS
}


sub help_detail {
    return <<EOS
If give "-amos_file yes" option to run velvetg, velvet will generate velvet_asm.afg 
file that contains all contigs/reads assembly/alignment info. This tool will convert 
those info into acefile so assembly can be viewed/edited by using consed. Based on the
current setting, this tool can handle up to 25 million reads dataset with -sqlite-yes
option
EOS
}


sub create {
    my $class = shift;
    my $self  = $class->SUPER::create(@_);

    my $file = $self->afg_file;

    return $self->error_handle("Input velvet afg file: $file must NOT be valid or existing")
    unless -s $file and $file =~ /\.afg/;

    my $seq_file = $self->seq_file;
    unless ($seq_file and -s $seq_file) {
        $seq_file = (dirname $file) . '/Sequences';
        return $self->error_handle("Failed to find valid Sequences file to be index")
        unless -s $seq_file;
        $self->seq_file($seq_file);
    }

    my $out_file = $self->out_acefile;
    if (-s $out_file) {
        $self->warning_message("out_acefile: $out_file exists and will be overwritten"); 
        unlink $out_file;
    }

    if ($self->sqlite_yes) {
        my $rv = $self->get_sqlite_dbh;
        return unless $rv;
    }

    return $self;
}


sub execute {
    my $self = shift;

    print Cwd::cwd()."\n";
    my $time   = $self->time || localtime;
    my $dbh    = $self->_dbh if $self->sqlite_yes;

    #my $seqinfo  = {};
    my @seqinfo;
    my %read_dup = ();
    my $nReads   = 0;
    my $nContigs = 0;

    #velvet 7.44 uses the actual read name as the fasta header in Sequences file
    my $seq_fh  = Genome::Utility::FileSystem->open_file_for_reading($self->seq_file) or return;
    my $seekpos = $seq_fh->tell;

    my $io = Bio::SeqIO->new(-format => 'fasta', -fh => $seq_fh);
    my $ct = 0;

    #%seqinfo is 1-based.
    while (my $seq = $io->next_seq) {
        $ct++;
        my $name = $seq->display_id;

        if ($self->sqlite_yes) {
            my $sth = $dbh->prepare("insert into read_info (id, name, position) values ('$ct', '$name', '$seekpos')"); 
            $sth->execute or return $self->error_handle("Failed to insert for $name : ".$DBI::errstr);
        }
        else {
            #$seqinfo->{$ct}->{name} = $name;
	    push @{$seqinfo[$ct]}, $name;
            #$seqinfo->{$ct}->{pos}  = $seekpos;
	    push @{$seqinfo[$ct]}, $seekpos;
        }
        $seekpos = $seq_fh->tell;
    }
    $self->status_message('Finished storing read info');

    if ($self->sqlite_yes) {
        my $sth = $dbh->prepare('create unique index ids on read_info(id)');
        $sth->execute or return $self->error_handle('Failed to create index ids : '.$DBI::errstr);
        $dbh->commit;
    }

    $seq_fh->close;

    my $afg_file = $self->afg_file;
    my $afg_fh   = Genome::Utility::FileSystem->open_file_for_reading($afg_file) or return;
    my $out_ace  = $self->out_acefile;
    my $out      = Genome::Utility::FileSystem->open_file_for_writing($out_ace) or return;
    my $writer   = GSC::IO::Assembly::Ace::Writer->new($out);

    # Tmp writer for reads and read positions
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $reads_file = $tmpdir.'/reads';
    my $reads_fh = Genome::Utility::FileSystem->open_file_for_writing($reads_file)
        or return;
    my $read_writer = GSC::IO::Assembly::Ace::Writer->new($reads_fh)
        or return;
    my $read_pos_file = $tmpdir.'/read_positions';
    my $read_pos_fh = Genome::Utility::FileSystem->open_file_for_writing($read_pos_file)
        or return;
    my $read_pos_writer = GSC::IO::Assembly::Ace::Writer->new($read_pos_fh)
        or return;

    while (my $record = getRecord($afg_fh)){
        my ($rec, $fields, $recs) = parseRecord($record);
        my $nseqs = 0;

        if ($rec eq 'CTG') {
            $nContigs++;
            my $ctg_seq = $fields->{seq};
            $ctg_seq =~ s/\n//g;
            $ctg_seq =~ s/-/*/g;

            my $ctg_id = $fields->{eid};
            if ($ctg_id =~ /\-/) {
                my ($scaf_num, $ctg_num) = split /\-/, $ctg_id;
                $scaf_num--; #To fit silly pcap scaffold naming
                $ctg_num++;  #To fit silly pcap contig naming
                $ctg_id = 'Contig'.$scaf_num.".$ctg_num";
            }
            else {
                $ctg_id = 'Contig'.$ctg_id;
            }

            my $ctg_length = length $ctg_seq;

            my $ctg_qual = $fields->{qlt};
            $ctg_qual =~ s/\n//g;

            my @ctg_quals;
            for my $i (0..length($ctg_qual)-1) {
                unless (substr($ctg_seq, $i, 1) eq '*') {
                    push @ctg_quals, ord(substr($ctg_qual, $i, 1)) - ord('0');
                }
            }

            my %left_pos;
            my %right_pos;
            my $nRd = 0;
            for my $r (0..$#$recs) {
                my ($srec, $sfields, $srecs) = parseRecord($recs->[$r]);

                if ($srec eq 'TLE') {
                    my $ori_read_id = $sfields->{src};
                    return $self->error_handle('TLE record contains no src: field')
                    unless defined $ori_read_id;

                    my ($read_id, $pos, $itr);

                    if ($self->sqlite_yes) { #<--------------------
                        my $sth = $dbh->prepare(
                            qq(
                            select name, position 
                            from read_info 
                            where id = '$ori_read_id'
                            )
                        );
                        $sth->execute or return $self->error_handle("Failed to select for read: $ori_read_id ".$DBI::errstr);
                        my @out = $sth->fetchrow_array;
                        return $self->error_handle("Got nothing from sqlite select for read: $ori_read_id") unless @out;

                        ($read_id, $pos) = @out;
                        $read_id .= '-'.$read_dup{$ori_read_id} if exists $read_dup{$ori_read_id};
                        $read_dup{$ori_read_id}++;
                    }
                    else {
			#my $info = $seqinfo->{$ori_read_id};
                        #return $self->error_handle("Sequence of $ori_read_id (iid) not found") unless $info;
			#$read_id = $info->{name};
                        #$pos     = $info->{pos};
                        #$read_id .= '-' . $info->{ct} if exists $info->{ct};
                        #$seqinfo->{$ori_read_id}->{ct}++;
			#converted hash of hash to array or array to reduce foot print
			return $self->error_handle("Sequence of $ori_read_id (iid) not found") unless
			    defined $seqinfo[$ori_read_id];
			$read_id = ${$seqinfo[$ori_read_id]}[0];
			$pos = ${$seqinfo[$ori_read_id]}[1];
			$read_id .= '-' . ${$seqinfo[$ori_read_id]}[2] if defined ${$seqinfo[$ori_read_id]}[2];
			${$seqinfo[$ori_read_id]}[2]++;
		    }
                    $dbh->commit if $self->sqlite_yes;

                    my $sequence = $self->get_seq($pos, $read_id, $ori_read_id);

                    return unless $sequence;

                    my ($asml, $asmr) = split (/\,/, $sfields->{clr});

                    ($asml, $asmr) = $asml < $asmr ? (0, $asmr - $asml) : ($asml - $asmr, 0);

                    my ($seql, $seqr) = ($asml, $asmr);

                    my $ori = ($seql > $seqr) ? 'C' : 'U';
                    $asml += $sfields->{off};
                    $asmr += $sfields->{off};

                    if ($asml > $asmr){
                        $sequence = reverseComplement($sequence);
                        my $tmp = $asmr;
                        $asmr = $asml;
                        $asml = $tmp;

                        $tmp  = $seqr;
                        $seqr = $seql;
                        $seql = $tmp;
                    }

                    my $off = $sfields->{off} + 1;

                    $asml = 0 if $asml < 0;
                    $left_pos{$read_id}  = $asml + 1;
                    $right_pos{$read_id} = $asmr;

                    my $end5 = $seql + 1;
                    my $end3 = $seqr;

                    # Write read position to tmp file
                    $read_pos_writer->write_object(
                        {
                            type      => 'read_position',
                            read_name => $read_id,
                            u_or_c    => $ori,
                            position  => $off,
                        }
                    );

                    # Write read to tmp file
                    $read_writer->write_object(
                        {
                            type              => 'read',
                            name              => $read_id,
                            padded_base_count => length $sequence,
                            info_count        => 0, 
                            tag_count         => 0,
                            sequence          => $sequence,
                            qual_clip_start   => $end5,
                            qual_clip_end     => $end3,
                            align_clip_start  => $end5,
                            align_clip_end    => $end3,
                            description       => {
                                CHROMAT_FILE => $read_id,
                                PHD_FILE     => $read_id.'.phd.1',
                                TIME         => $time,
                            },
                        }
                    );
                    $nRd++; # read count
                }         
            }

            # Write contig
            # WAS: map{$writer->write_object($_)}($contig, @read_pos, @base_segments, @reads);
            
            # Get base segments to get count - may have to write to tmp file
            my @base_segments = get_base_segments(\%left_pos, \%right_pos, $ctg_length);

            # Contig - use ace writer
            $writer->write_object(
                {
                    type           => 'contig',
                    name           => $ctg_id,
                    base_count     => $ctg_length,
                    read_count     => $nRd,
                    base_seg_count => scalar(@base_segments),
                    u_or_c         => 'U',
                    consensus      => $ctg_seq,
                    base_qualities => \@ctg_quals,
                }
            );
            $nReads += $nRd;

            # Read positions - use tmp read positions file to write to ace fh
            $read_pos_fh->close;
            my $read_pos_rfh = Genome::Utility::FileSystem->open_file_for_reading(
                $read_pos_file
            ) or return;
            while ( my $line  = $read_pos_rfh->getline ) {
                $out->print($line);
            }
            $read_pos_rfh->close;
            unlink $read_pos_file;
            $read_pos_fh = Genome::Utility::FileSystem->open_file_for_writing(
                $read_pos_file
            ) or return;
            $read_pos_writer = GSC::IO::Assembly::Ace::Writer->new($read_pos_fh)
                or return;

            # Base segments - use ace writer
            for my $base_segment ( @base_segments ) {
                $writer->write_object($base_segment);
            }

            # Reads - use tmp reads file to write to ace fh
            $reads_fh->close;
            my $reads_rfh = Genome::Utility::FileSystem->open_file_for_reading(
                $reads_file
            ) or return;
            while ( my $line = $reads_rfh->getline ) {
                $out->print($line);
            }
            $reads_rfh->close;
            unlink $reads_file;
            $reads_fh = Genome::Utility::FileSystem->open_file_for_writing(
                $reads_file
            ) or return;
            $read_writer = GSC::IO::Assembly::Ace::Writer->new($reads_fh)
                or return;

            $self->status_message("$nContigs contigs are done") if $nContigs % 100 == 0;
        }#if 'CTG'
    }#While loop
    $afg_fh->close;
    #$seq_fh->close;
    $self->status_message("There are total $nContigs contigs and $nReads reads processed");

    $writer->write_object({
            type     => 'assembly_tag',
            tag_type => 'comment',
            program  => 'VelvetToAce',
            date     => time2str('%y%m%d:%H%M%S', time),
            data     => "Run by $ENV{USER}\n",
        });
    $out->close;

    my $tmp_ace = $out_ace . '.tmp';

    my $rv = Genome::Utility::FileSystem->shellcmd(
        cmd => "mv $out_ace $tmp_ace",
        output_files => [$tmp_ace],
        skip_if_output_is_present => 0,
    );

    unless ($rv == 1) {
        $self->error_message('Failed to mv ace file to ace.tmp');
        return;
    }

    my $out_fh = Genome::Utility::FileSystem->open_file_for_writing($out_ace) or return;
    $out_fh->print("AS $nContigs $nReads\n");
    $out_fh->close;

    $rv = Genome::Utility::FileSystem->shellcmd(
        cmd => "cat $tmp_ace >> $out_ace",
        output_files => [$out_ace],
        skip_if_output_is_present => 0,
    );

    unless ($rv == 1) {
        $self->error_message('Failed to cat ace header line to acefile');
        return;
    }

    unlink $tmp_ace;    
    return 1;
}


sub get_sqlite_dbh {
    my $self = shift;

    my $db_file = (dirname $self->afg_file) .'/velvet_reads.sqlite';
    unlink $db_file;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { AutoCommit => 0, RaiseError => 1 })
        or return $self->error_handle("Failed to connect to db ($db_file): " . $DBI::errstr);

    my $sth = $dbh->prepare('create table read_info (id integer, name string, position integer)');
    $sth->execute or return $self->error_handle('Failed to create table read_info : '.$DBI::errstr);
    $dbh->commit;

    $self->{_dbh} = $dbh;
    return 1;
}


sub get_seq {
    my ($self, $seekpos, $name, $id) = @_;

    my $fh = Genome::Utility::FileSystem->open_file_for_reading($self->seq_file) or return;
    $fh->seek($seekpos, 0);
    my $fa_bio = Bio::SeqIO->new(-fh => $fh, -format => 'fasta');
    my $fasta  = $fa_bio->next_seq;

    return $self->error_handle("Failed to get fasta bio obj from $name, $seekpos, $id")
    unless $fasta;

    my $sequence = $fasta->seq;
    my $seq_name = $fasta->display_id;

    return $self->error_handle("Failed to get fasta seq for read $name, $id") 
    unless $sequence;
    return $self->error_handle("Failed to match seq name: $name => $seq_name")
    unless $name =~ /$seq_name/;

    return $sequence;
}


sub get_base_segments {
    my ($left_pos, $right_pos, $ctg_length) = @_;

    my $prev; 
    my @base_segs;

    for my $seq (sort { ($left_pos->{$a} == $left_pos->{$b}) ? ($right_pos->{$b} <=> $right_pos->{$a}) : ($left_pos->{$a} <=> $left_pos->{$b}) } (keys %$left_pos)) {
        if (defined $prev) {
            if ($left_pos->{$seq} -1 < $left_pos->{$prev} || $right_pos->{$seq} < $right_pos->{$prev}) {
                next;
            }
            push @base_segs, {
                type      => 'base_segment',
                start_pos => $left_pos->{$prev},
                end_pos   => $left_pos->{$seq} - 1,
                read_name => $prev,
            };
        }
        $prev = $seq;
    }

    push @base_segs, {
        type      => 'base_segment',
        start_pos => $left_pos->{$prev},
        end_pos   => $ctg_length,
        read_name => $prev,
    };
    return @base_segs;
}

sub error_handle {
    my ($self, $msg) = @_;
    $self->error_message($msg);
    return;
}


sub _dbh {
    return shift->{_dbh};
}


1;
#$HeadURL$
#$Id$


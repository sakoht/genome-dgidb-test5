package Genome::InstrumentData::AlignmentResult::Command::VerifyDt;

use strict;
use warnings;
use Genome;
use DateTime;

class Genome::InstrumentData::AlignmentResult::Command::VerifyDt {
    is => 'Genome::Command::Base',
    has => [
        instrument_data => {
            is => 'Genome::InstrumentData',
            is_many => 1,
            doc => 'The instrument data to locate alignment results (and merged BAMs).',
            shell_args_position => 1,
        },
        repair => {
            is => 'Boolean',
            default => 0,
            doc => 'Attempt to repair BAMs.',
        }
    ],
    doc => 'Verify that the timestamps in the BAM file are ISO 8601 formatted.',
};

sub help_synopsis {
    my $class = shift;
    return <<EOS;
genome instrument-data alignment-result verify-timestamps 123456,456789
genome instrument-data alignment-result verify-timestamps --instrument-data=123456,456789
EOS
}

sub help_detail {
    my $class = shift;
    return <<'EOS';
Verify that the timestamps in the BAM file are ISO 8601 formatted.
EOS
}

sub execute {
    my $self = shift;
    my @instrument_data_ids = map { $_->id } $self->instrument_data;

    my @bams;
    for my $instrument_data_id (@instrument_data_ids) {
        my @alignment_results = Genome::InstrumentData::AlignmentResult->get(
            instrument_data_id => $instrument_data_id
        );
        for my $alignment_result (@alignment_results) {
            push @bams, $alignment_result->output_dir . "/all_sequences.bam";
            my @builds = map { Genome::Model::Build->get($_->user_id) } $alignment_result->users;
            for my $build (@builds) {
                my @merged_bams = glob($build->data_directory . "/alignments/*_merged_rmdup.bam");
                @merged_bams = grep { $_ =~ /\/\d+_merged_rmdup.bam/ } @merged_bams;
                push @bams, @merged_bams;
            }
        }
    }

    for my $in_bam (@bams) {
        if (-f $in_bam && -s $in_bam) {
            unless(valid_dt_tag($in_bam)) {
                repair_dt($in_bam) if ($self->repair);
            }
        } else {
            print "BAM ($in_bam) does not appear to be a valid file:\n";
            system("ls $in_bam");
        }
    }

}

sub valid_dt_tag {
    my $file = shift;
    chomp(my @dt_lines = qx(samtools view -H $file | grep DT:));
    my $valid = 1;
    for my $dt_line (@dt_lines) {
        my @tags = split("\t", $dt_line);
        my ($dt_tag) = grep { $_ =~ /^DT:/ } @tags;
        if ($dt_tag =~ /^DT:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}$/
            || $dt_tag =~ /^DT:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) {
            print "Valid: ($dt_tag) $file\n";
        } elsif ($dt_tag) {
            print "Invalid: ($dt_tag) $file\n";
            $valid = 0;
        } else {
            print "Missing DT tag: $file\n";
        }
    }
    return $valid;
}

sub repair_dt {
    my $in_bam = shift;
    (my $in_sam_h = $in_bam) =~ s/\.bam$/.sam.h/;
    (my $out_bam = $in_bam) =~ s/\.bam$/_fixed.bam/;
    (my $out_sam_h = $in_sam_h) =~ s/\.sam\.h$/_fixed.sam.h/;
    system("samtools view -H $in_bam > $in_sam_h") && die;
    chomp(my @dt_lines = qx(samtools view -H $in_bam | grep DT:));
    print "Repairing headers...\n";
    for my $dt_line (@dt_lines) {
        my @tags = split("\t", $dt_line);
        my ($dt_tag) = grep { $_ =~ /^DT:/ } @tags;
        unless ($dt_tag) {
            print "Could not find DT tag: $dt_line.\n";
            next;
        }
        my ($year, $month, $day, $hour, $min, $sec) = $dt_tag =~ /DT:(\d{4})-(\d{2})-(\d{2})\ (\d{2}):(\d{2}):(\d{2})/;
        unless ($sec) {
            print "Unmatched DT tag: $dt_tag.\n";
            next;
        }
        my $datetime = DateTime->new(
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $min,
            second    => $sec,
            time_zone => 'America/Chicago',
        );
        $datetime->set_time_zone('UTC');
        my $new_dt_tag = "DT:${datetime}Z";
        print "\tChanging DT tag from $dt_tag to $new_dt_tag.\n";
        $dt_tag =~ s/\ /\\ /;
        system("cat $in_sam_h | sed 's/$dt_tag/$new_dt_tag/' > $out_sam_h") && die;
    }
    print "Repairing bam...\n";
    system("samtools reheader $out_sam_h $in_bam > $out_bam") && die;

    print "Validating new bam...\n";
    my $in_bam_md5 = qx(samtools view $in_bam | md5sum);
    my $out_bam_md5 = qx(samtools view $out_bam | md5sum);
    if ($in_bam_md5 eq $out_bam_md5) {
        rename($in_bam, "$in_bam.orig") || die;
        rename($out_bam, $in_bam) || die;
        unlink("$in_bam.md5") || die;
        !system("md5sum $in_bam > $in_bam.md5") || die;
        chmod(0444, "$in_bam.md5") || die;
        chmod(0444, "$in_bam") || die;
        unlink("$in_bam.orig") || die;
        unlink($out_sam_h) || die;
        unlink($in_sam_h) || die;
    } else {
        print "\tERROR: BAM contents mismatch between $in_bam and $out_bam.\n";
    }
    print "\n";
}


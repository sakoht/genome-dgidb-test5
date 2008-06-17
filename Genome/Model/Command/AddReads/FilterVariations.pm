package Genome::Model::Command::AddReads::FilterVariations;

use strict;
use warnings;

use above "Genome";
use Command; 

use FileHandle;

class Genome::Model::Command::AddReads::FilterVariations {
    is => ['Genome::Model::EventWithRefSeq'],
    sub_classification_method_name => 'class',
    has => [
#        normal_id            => { is => 'Integer', 
#                                doc => 'Identifies the normal genome model.' },
    ]
};

sub sub_command_sort_position { 90 }

sub help_brief {
    "Create filtered lists of variations."
}

sub help_synopsis {
    return <<"EOS"
    genome-model postprocess-alignments filter-variations --model-id 5 --ref-seq-id 22 
EOS
}

sub help_detail {
    return <<"EOS"
Create filtered list(s) of variations.
EOS
}

sub GetNormal {
	my ($self, $ref_seq_file, $detail_file_sort, $alignment_quality) = @_;
	my $chromosome = $self->ref_seq_id;
	my $model = $self->model;
	my ($detail_file) = $model->_variant_detail_files($chromosome);
	my $normal_name = '2509660674';
	#my $normal_name = $self->normal_id;
	my @normal_model = Genome::Model->get(id => $normal_name );
	unless (scalar(@normal_model)) {
		$self->error_message(sprintf("normal model %s does not exist.  please verify this first.",
																 $normal_name));
		return undef;
	}
	my %normal;

	my $map_file_path =
		$normal_model[0]->resolve_accumulated_alignments_filename(
																															ref_seq_id => $chromosome,
																														 );
	my $ov_cmd = "/gscuser/bshore/src/perl_modules/Genome/Model/Tools/Maq/ovsrc/maqval $map_file_path $detail_file_sort $alignment_quality |";
	my $ov_fh = IO::File->new($ov_cmd);
	unless ($ov_fh) {
		$self->error_message("Unable to get counts $$");
		return;
	}
	while (<$ov_fh>) {
		chomp;
		unless (/^\d+\s+/) {
			next;
		}
#RC(A,C,G,T) URC(A,C,G,T) URSC(A,C,G,T) REF Ref(RC,URC,URSC,Q,MQ) Var1(RC,URC,URSC,Q,MQ) Var2(RC,URC,URSC,Q,MQ)
		my ($chr, $start, $ref_sequence, $iub_sequence, $quality_score,
				$rc_arr, $empty3, $urc_arr, $ursc_arr, $ref,
				$ref_count_arr, $empty4, $al1_count_arr, $empty5, $al2_count_arr) =
					split("\t");
		my ($ref_rc, $ref_urc, $ref_ursc, $ref_bq, $ref_maxbq) =
			split(',',$ref_count_arr);
		my ($al1_rc, $al1_urc, $al1_ursc, $al1_bq, $al1_maxbq) =
			split(',',$al1_count_arr);
		my ($al2_rc, $al2_urc, $al2_ursc, $al2_bq, $al2_maxbq) =
			split(',',$al2_count_arr);
		$normal{$chr}{$start}{ref_rc} = $ref_rc;
		$normal{$chr}{$start}{al1_rc} = $al1_rc;
		$normal{$chr}{$start}{al2_rc} = $al2_rc;
	}
	$ov_fh->close;
	return \%normal;
}

my %IUBcode=(
	     A=>'AA',
	     C=>'CC',
	     G=>'GG',
	     T=>'TT',
	     M=>'AC',
	     K=>'GT',
	     Y=>'CT',
	     R=>'AG',
	     W=>'AT',
	     S=>'GC',
	     D=>'AGT',
	     B=>'CGT',
	     H=>'ACT',
	     V=>'ACG',
	     N=>'ACGT',
	    );

sub SNPFiltered {
	my ($self, $snp_file_filtered) = @_;
	my $chromosome = $self->ref_seq_id;
	my $model = $self->model;

	my ($snp_file) = $model->_variant_list_files($chromosome);
	my $snp_fh = IO::File->new($snp_file);
	unless ($snp_fh) {
		$self->error_message(sprintf("snp file %s does not exist.  please verify this first.",
																 $snp_file));
		return 0;
	}
	my $snp_filtered_fh = IO::File->new(">$snp_file_filtered");
	unless ($snp_filtered_fh) {
		$self->error_message(sprintf("snp file %s can not be created.",
																 $snp_file_filtered));
		return 0;
	}
	while (<$snp_fh>) {
		chomp;
		my ($id, $start, $ref_sequence, $iub_sequence, $quality_score,
				$depth, $avg_hits, $high_quality, $unknown) = split("\t");
		my $genotype = $IUBcode{$iub_sequence};
		my $cns_sequence = substr($genotype,0,1);
		my $var_sequence = (length($genotype) > 2) ? 'X' : substr($genotype,1,1);
		if ($ref_sequence eq $cns_sequence &&
				$ref_sequence eq $var_sequence) {
			next;										# no variation
		}
		if ($depth > 2) {
			print $snp_filtered_fh $_ . "\n";
		}
	}
	$snp_fh->close;
	$snp_filtered_fh->close;
	return 1;
}

sub execute {
    my $self = shift;
    $DB::single = 1; # when debugging, stop here...
    
    my $chromosome = $self->ref_seq_id;
    my $model = $self->model;

    my ($snp_file) = $model->_variant_list_files($chromosome);
    my ($pileup_file) = $model->_variant_pileup_files($chromosome);
    my ($detail_file) = $model->_variant_detail_files($chromosome);

		# ensure the reference sequence exists.
    my $ref_seq_file =  $model->reference_sequence_path . "/all_sequences.bfa";
    
    unless (-e $ref_seq_file) {
			$self->error_message(sprintf("reference sequence file %s does not exist.  please verify this first.", $ref_seq_file));
			return;
    }

    my ($filtered_list_dir) = $model->_filtered_variants_dir();
    print "$filtered_list_dir\n";
    unless (-d $filtered_list_dir) {
        mkdir $filtered_list_dir;
        `chmod g+w $filtered_list_dir`;
    }

		my $snp_file_filtered = $filtered_list_dir . "snp_filtered_${chromosome}.csv";

		unless ($self->SNPFiltered($snp_file_filtered)) {
			return;
		}

    # This creates a map file in /tmp which is actually a named pipe
    # streaming the data from the original maps.
    # It can be used only once.  Run this again if you need to use it multiple times.
    my $map_file_path = $model->resolve_accumulated_alignments_filename(
																																				ref_seq_id => $chromosome,
																																			 );

		my $snp_file_sort = $filtered_list_dir . "snp_filtered_sort_${chromosome}.csv";
		system("perl /gscuser/jschindl/snp_sort.pl $snp_file_filtered $map_file_path $snp_file_sort $chromosome");

		my $alignment_quality = 1;
		my $normal_href = $self->GetNormal($ref_seq_file, $snp_file_sort, $alignment_quality);
		unless (defined($normal_href)) {
			return;
		}

		my ($file, $basename, $qvalue_level, $bq);
		my $specificity = 'default';
		my $ruleset = 'dtr2a';
		#my $ruleset = 'dtr3e';



		my %specificity_maqq;
		if ($ruleset eq 'dtr2a') {
			%specificity_maqq = (
												max => [ 121, 0 ],
												95 => [ 110, 0 ],
												90 => [ 70, 0 ],
												75 => [ 30, 0 ],
												default => [ 29, 0 ],
												min => [ 29, 0 ]
											 );
		} else {
			%specificity_maqq = (
													 min => [ 5, 16 ],
													 default => [ 30, 16 ],
													 90 => [ 40, 22 ],
													 95 => [ 50, 26 ],
													 max => [ 120, 26 ],
													);
		}

		my $spec_ref = (exists($specificity_maqq{$specificity})) ?
			$specificity_maqq{$specificity} : $specificity_maqq{default};
		($qvalue_level, $bq) = @$spec_ref;
		$qvalue_level ||= 30;
		$bq ||= 16;

		$basename = $filtered_list_dir . '/filtered';

		my %lib_urc;
    my @libraries = $model->libraries;
		my $library_number = 0;
		foreach my $library_name (@libraries) {
				# This creates a map file in /tmp which is actually a named pipe
				# streaming the data from the original maps.
				# It can be used only once.  Run this again if you need to use it multiple times.
				my $lib_map_file_path = $model->resolve_accumulated_alignments_filename(
																																						ref_seq_id => $chromosome,
																																						library_name => $library_name, # optional
																																					 );
				$library_number += 1;
				my $ov_lib_cmd = "/gscuser/bshore/src/perl_modules/Genome/Model/Tools/Maq/ovsrc/maqval $lib_map_file_path $snp_file_sort $alignment_quality |";

				my $ov_lib_fh = IO::File->new($ov_lib_cmd);
				unless ($ov_lib_fh) {
					$self->error_message("Unable to get counts for $chromosome $library_name $$");
					return;
				}
				while (<$ov_lib_fh>) {
					chomp;
					unless (/^\d+\s+/) {
						next;
					}
					#RC(A,C,G,T) URC(A,C,G,T) URSC(A,C,G,T) REF Ref(RC,URC,URSC,Q,MQ) Var1(RC,URC,URSC,Q,MQ) Var2(RC,URC,URSC,Q,MQ)
					
					my ($lib_chr, $lib_start, $lib_ref_sequence, $lib_iub_sequence, $lib_quality_score,
							$lib_depth, $lib_avg_hits, $lib_high_quality, $lib_unknown,
							$lib_rc_arr, $lib_empty3, $lib_urc_arr, $lib_ursc_arr, $lib_ref,
							$lib_ref_count_arr, $lib_empty4, $lib_al1_count_arr, $lib_empty5, $lib_al2_count_arr) =
								split("\t");
					my ($lib_al1_rc, $lib_al1_urc, $lib_al1_ursc, $lib_al1_bq, $lib_al1_maxbq) =
						split(',',$lib_al1_count_arr);
					$lib_urc{$library_number}{$lib_chr}{$lib_start}{al1_ursc} = $lib_al1_ursc;
				}
				$ov_lib_fh->close();
			}

		my $use_validation = 1;
		my $status_file = '/gscmnt/sata180/info/medseq/dlarson/aml_temp_consolidate_08520.csv';
		my %status;
		open(STATUS,$status_file);
		while (<STATUS>) {
			chomp;
			my ($chr, $pos, $status) = split("\t");
			$status ||= '';
			unless ($status =~ /^\s*$/) {
				$status{$chr}{$pos} = $status;
			}
		}
		close(STATUS);




		$file = '/gscmnt/sata180/info/medseq/bshore/amll123t98_annotation/amll123t98_all_SNPs_with_conservation_new.bq.validation.csv';
		my @values_used = ( 2, 3, 4, 28,  5, 6, 10, 11, 37, 39, 41, 33, 9, 60, 63, 64 );
		my $header = new FileHandle;
		$header->open($file, "r") or die "Couldn't open annotation file\n";
		my $header_line = $header->getline; #ignore header
		my $somatic_handle = new FileHandle;
		my $keep_handle = new FileHandle;
		my $remove_handle = new FileHandle;
		my $report_handle = new FileHandle;
		my $invalue_handle = new FileHandle;
		my $somatic_file = $basename . '.chr' . $chromosome . '.somatic.csv';
		my $keep_file = $basename . '.chr' . $chromosome . '.keep.csv';
		my $remove_file = $basename . '.chr' . $chromosome . '.remove.csv';
		my $report_file = $basename . '.chr' . $chromosome . '.report.csv';
		my $invalue_file = $basename . '.chr' . $chromosome . '.input.csv';
		$somatic_handle->open("$somatic_file","w") or die "Couldn't open keep output file\n";
		$keep_handle->open("$keep_file","w") or die "Couldn't open keep output file\n";
		$remove_handle->open("$remove_file","w") or die "Couldn't open remove output file\n";
		$report_handle->open("$report_file","w") or die "Couldn't open report output file\n";
		$invalue_handle->open("$invalue_file","w") or die "Couldn't open input value (output) file\n";
		
		chomp $header_line;
		my $validation_header = '';
#		if ($use_validation) {
#			$validation_header = ',validation_status';
#		}
		print $somatic_handle $header_line . "$validation_header,rule\n";
		print $keep_handle $header_line . "$validation_header,rule\n";
		print $remove_handle $header_line . "$validation_header,rule\n";
		
		my %result = ();
		
		#print new header

    # This creates a map file in /tmp which is actually a named pipe
    # streaming the data from the original maps.
    # It can be used only once.  Run this again if you need to use it multiple times.
    $map_file_path = $model->resolve_accumulated_alignments_filename(
																																		 ref_seq_id => $chromosome,
																																		);
    print "made map $map_file_path\n";

		my $ov_cmd = "/gscuser/bshore/src/perl_modules/Genome/Model/Tools/Maq/ovsrc/maqval $map_file_path $snp_file_sort $alignment_quality |";

    my $ov_fh = IO::File->new($ov_cmd);
		unless ($ov_fh) {
			$self->error_message("Unable to get counts $$");
			return;
		}

#		while(my $line=$header->getline) {
#			chomp $line;
#			$line =~ s/NULL/0/g;
#			my @values = split ",", $line;
#			my (
#					$chr,
#					$start,
#					$end,
#					$al1,
#					$al2,
##					$al1_type,
##					$al2_type,
##					$rgg_id,
##					$ref,
#					$al2_read_hg,
#					$al2_read_unique_dna_start,
#					$al2_read_unique_dna_context,
#					$lib1_al1_read_unique_dna_context,
#					$lib2_al1_read_unique_dna_context,
#					$lib3_al1_read_unique_dna_context,
#					$al1_read_unique_dna_start,
#					$al2_read_skin_dna,
#					$qvalue,
#					$base_quality,
#					$max_base_quality
#				 ) = @values[@values_used];
#			my $al1_type = 'ref';
#			my $al2_type = 'SNP';
			
		while (<$ov_fh>) {
			chomp;
			unless (/^\d+\s+/) {
				next;
			}
#RC(A,C,G,T) URC(A,C,G,T) URSC(A,C,G,T) REF Ref(RC,URC,URSC,Q,MQ) Var1(RC,URC,URSC,Q,MQ) Var2(RC,URC,URSC,Q,MQ)

		my ($chr, $start, $ref_sequence, $iub_sequence, $quality_score,
				$depth, $avg_hits, $high_quality, $unknown,
				$rc_arr, $empty3, $urc_arr, $ursc_arr, $ref,
				$ref_count_arr, $empty4, $al1_count_arr, $empty5, $al2_count_arr) =
						split("\t");
			my ($ref_rc, $ref_urc, $ref_ursc, $ref_bq, $ref_maxbq) =
				split(',',$ref_count_arr);
			my ($al1_rc, $al1_urc, $al1_ursc, $al1_bq, $al1_maxbq) =
				split(',',$al1_count_arr);
			my ($al2_rc, $al2_urc, $al2_ursc, $al2_bq, $al2_maxbq) =
				split(',',$al2_count_arr);

			my $genotype = $IUBcode{$iub_sequence};
			my $al1 = substr($genotype,0,1);
			my $al2 = (length($genotype) > 2) ? 'X' : substr($genotype,1,1);

			my (
					$end,
					$al1_type,
					$al2_type,
					$al2_read_hg,
					$al2_read_unique_dna_start,
					$al2_read_unique_dna_context,
					$lib1_al1_read_unique_dna_context,
					$lib2_al1_read_unique_dna_context,
					$lib3_al1_read_unique_dna_context,
					$al1_read_unique_dna_start,
					$al2_read_skin_dna,
					$qvalue,
					$base_quality,
					$max_base_quality
				 ) = 
					 (
						$start,
						($ref_sequence eq $al1) ? 'ref' : 'SNP',
						'SNP',
						$al2_rc,
						$al2_urc,
						$al2_ursc,
						$lib_urc{1}{$chr}{$start}{al1_ursc} || 0,
						$lib_urc{2}{$chr}{$start}{al1_ursc} || 0,
						$lib_urc{3}{$chr}{$start}{al1_ursc} || 0,
						$ref_urc,
						$normal_href->{$chr}{$start}{al2_rc} || 0,
						$quality_score,
						$al2_bq,
						$al2_maxbq,
					 );
			my $line = 
				join("\t",
						 (
							$chr,
							$start,
							$end,
							$al1,
							$al2,
							$al1_type,
							$al2_type,
							$al2_read_hg,
							$al2_read_unique_dna_start,
							$al2_read_unique_dna_context,
							$lib1_al1_read_unique_dna_context,
							$lib2_al1_read_unique_dna_context,
							$lib3_al1_read_unique_dna_context,
							$al1_read_unique_dna_start,
							$al2_read_skin_dna,
							$qvalue,
							$base_quality,
							$max_base_quality
						 ));

			
			print $invalue_handle join("\t",
																 (
																	$chr,
																	$start,
																	$end,
																	$al1,
																	$al2,
																	$al1_type,
																	$al2_type,
																	$al2_read_hg,
																	$al2_read_unique_dna_start,
																	$al2_read_unique_dna_context,
																	$lib1_al1_read_unique_dna_context,
																	$lib2_al1_read_unique_dna_context,
																	$lib3_al1_read_unique_dna_context,
																	$al1_read_unique_dna_start,
																	$al2_read_skin_dna,
																	$qvalue,
																	$base_quality,
																	$max_base_quality
																 )) . "\n";

			my $validation;
			if (exists($status{$chr}{$start})) {
				$validation = $status{$chr}{$start};
			}
			$validation ||= '0';
			my $decision = 'keep';
			my $rule = 'none';
			
			# dtr2a rules
			if ($ruleset eq 'dtr2a') {
				if ($al2_read_hg > 9 &&
						$al2_read_unique_dna_start <= 4) {
					#Rule 8:
					#    	# of genomic reads supporting variant allele > 9
					#    	# of unique genomic reads supporting variant allele(starting point) <= 4
					#	->  class WT  [93.9%]
					#
					$decision = 'remove';
					$rule = '8';
				} elsif ($al1_read_unique_dna_start > 15) {
					#Rule 14:
					#    	# of unique genomic reads supporting reference allele(starting point) > 15
					#	->  class WT  [89.9%]
					#
					$decision = 'remove';
					$rule = '14';
				} elsif ($al1_read_unique_dna_start <= 15 &&
								 $qvalue < $qvalue_level) {
					# qvalue:
					# 29  is > 74% (74.46%) Specifity (91.06% Sensitivity),
					# 30  is > 75% (74.85%) Specifity (91.06% Sensitivity),
					# 70  is > 90% (90.77%) Specifity (75.50% Sensitivity),
					# 110 is > 95% (95.48%) Specifity (53.31% Sensitivity)
					#Rule 2:
					#    	# of unique genomic reads supporting reference allele(starting point) <= 15
					#    	Maq SNP q-value <= 28
					#	->  class WT  [78.4%]
					#
					$decision = 'remove';
					$rule = '2';
				} elsif ($al2_read_unique_dna_start > 4 &&
								 $al1_read_unique_dna_start <= 15 &&
								 $qvalue > 33) {
					#Rule 13:
					#    	# of unique genomic reads supporting variant allele(starting point) > 4
					#    	# of unique genomic reads supporting reference allele(starting point) <= 15
					#    	Maq SNP q-value > 33
					#	->  class G  [88.9%]
					$decision = 'keep';
					$rule = '13';
				} elsif ($al2_read_unique_dna_start <= 3 &&
								 $al2_read_unique_dna_context > 3  &&
								 $lib1_al1_read_unique_dna_context <= 5 &&
								 $lib2_al1_read_unique_dna_context <= 5 &&
								 $lib3_al1_read_unique_dna_context <= 5
								 #						 $lib1_al1_read_unique_dna_context <= 4 &&
								 #						 $lib2_al1_read_unique_dna_context <= 4 &&
								 #						 $lib3_al1_read_unique_dna_context <= 4
								) {
					#Rule 5:
					#    	# of unique genomic reads supporting variant allele(starting point) <= 3
					#    	# of unique genomic reads supporting variant allele(context) > 3
					#    	# of unique genomic reads supporting reference allele from lib1 in first 26 bp(context) <= 4
					#	->  class WT  [87.1%]
					#
					$decision = 'remove';
					$rule = '5';
					#		} elsif ($al2_read_unique_cDNA_start_pre27 <= 9 &&
					#						 $al1_read_unique_dna_start_pre27 > 9) {
					#			#Rule 12:
					#			#    	# of unique cDNA reads supporting variant allele in first 26 bp(starting point) <= 9
					#			#    	# of unique genomic reads supporting reference allele in first 26 bp(starting point) > 9
					#			#	->  class WT  [70.7%]
					#			#
					#			$decision = 'remove';
					#			$rule = '12';
					# Rule 12 removes somatic SNPs--not allowed!!!
				} else {
					#Default class: G
					$decision = 'keep';
					$rule = 'default';
				}
			} elsif ($ruleset eq 'dtr3e') {
				# dtr3e rules
				if ($al2_read_unique_dna_start > 7 &&
						$qvalue >= $qvalue_level) {
					#Rule 5:
					#    	# of unique genomic reads supporting variant allele(starting point) > 7
					#	->  class G  [96.8%]
					#
					$decision = 'keep';
					$rule = '5';
					#		} elsif ($al2_read_unique_dna_start > 2 &&
					#						 $base_quality <= $bq + 2) {
					#			#Rule 2:
					#			#    	# of unique genomic reads supporting variant allele(starting point) > 2
					#			#    	Base Quality > 18
					#			#	->  class G  [90.7%]
					#			#
					#			$decision = 'keep';
					#			$rule = '2';
				} elsif ($max_base_quality <= 26) {
					#Rule 11:
					#    	Max Base Quality <= 26
					#	->  class WT  [85.2%]
					#
					$decision = 'remove';
					$rule = '11';
				} elsif ($al2_read_unique_dna_start <= 7 &&
								 $qvalue < $qvalue_level) {
					#Rule 7:
					#    	# of unique genomic reads supporting variant allele(starting point) <= 7
					#    	Maq SNP q-value <= 29
					#	->  class WT  [81.5%]
					#
					$decision = 'remove';
					$rule = '7';
				} elsif ($al2_read_unique_dna_start <= 2) {
					#Rule 8:
					#    	# of unique genomic reads supporting variant allele(starting point) <= 2
					#	->  class WT  [74.7%]
					#
					$decision = 'remove';
					$rule = '8';
				} elsif ($base_quality <= $bq) {
					#Rule 3:
					#    	Base Quality <= 16
					#	->  class WT  [73.0%]
					#
					$decision = 'remove';
					$rule = '3';
				} else {
					#Default class: G
					$decision = 'keep';
					$rule = 'default';
				}
			} else {
				return;
			}
		
			my $output_validation = '';
			if ($use_validation) {
				$result{$decision}{$validation}{n} += 1;
				$result{$decision}{$validation}{rule}{$rule} += 1;
#				$output_validation = ",$validation";
			}
			if ($decision eq 'keep') {
				if ($al2_read_skin_dna == 0) {
					$decision = 'somatic';
				}
			}
			if ($decision eq 'keep') {
				print $keep_handle $line,"$output_validation,$rule\n";    
			} elsif ($decision eq 'somatic') {
				print $somatic_handle $line,"$output_validation,$rule\n";    
				print $keep_handle $line,"$output_validation,$rule\n";    
			} else {
				print $remove_handle $line,"$output_validation,$rule\n";    
			}
		}
		$somatic_handle->close();
		$keep_handle->close();
		$remove_handle->close();
		$invalue_handle->close();
		$header->close();
		$ov_fh->close;
		
		my $keep_wt = 0;
		my $total_wt = 0;
		my $keep_g = 0;
		my $total_g = 0;
		foreach my $type (sort (keys %result)) {
			print $report_handle "$type\n";
			foreach my $status (sort (keys %{$result{$type}})) {
				my $n = $result{$type}{$status}{n};
				if ($status eq 'WT') {
					$total_wt += $n;
					if ($type eq 'remove') {
						$keep_wt += $n;
					}
				}
				if ($status eq 'G') {
					$total_g += $n;
					if ($type eq 'keep') {
						$keep_g += $n;
					}
				}
				my @rules;
				foreach my $rule_used (sort (keys %{$result{$type}{$status}{rule}})) {
					push @rules, (join(':',($rule_used, $result{$type}{$status}{rule}{$rule_used})));
				}
				print $report_handle "\t" . 
					join("\t",($status,$n,join(',',@rules))) . "\n";
			}
		}
		if ($total_wt > 0) {
			printf $report_handle "Specificity: %0.2f\n", (100.0 * ($keep_wt/$total_wt));
		}
		if ($total_g > 0) {
			printf $report_handle "Sensitivity: %0.2f\n", (100.0 * ($keep_g/$total_g));
		}
		
		# Clean up when we're done...
		$self->date_completed(UR::Time->now);
		if (0) { # replace w/ actual check
			$self->event_status("Failed");
			return;
		}
		else {
			$self->event_status("Succeeded");
			return 1;
		}
	}

1;


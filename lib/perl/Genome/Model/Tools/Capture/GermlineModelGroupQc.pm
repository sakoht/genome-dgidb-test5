package Genome::Model::Tools::Capture::GermlineModelGroupQc;
use strict;
use warnings;
use FileHandle;
use Genome;

my %stats = ();
my %already_reviewed = ();
my %wildtype_sites = my %germline_sites = ();

class Genome::Model::Tools::Capture::GermlineModelGroupQc {
    is => 'Command',                       
    
    has => [                                # specify the command's single-value properties (parameters) <--- 
        group_id        => { is => 'Text', doc => "ID of model group" , is_optional => 0},
        output_dir    => { is => 'Text', doc => "Outputs qc into directory for each sample" , is_optional => 0},
        summary_file    => { is => 'Text', doc => "Outputs qc summary into this file, must be run with already finished output (turns skip-if-output-present on)" , is_optional => 1},
        dbsnp_build    => { is => 'Text', doc => "dbsnp build to use: 130 for b36, 132 for b37" , is_optional => 0, default => 132},
        limit_snps_file    => { is => 'Text', doc => "File of snps to limit qc to, for example the 55 ASMS snps in ROI -- 1 rs_id per line" , is_optional => 1},
        data_source    => { is => 'Text', doc => "'internal', 'iscan', or 'external'" , is_optional => 0},
        skip_if_output_present    => { is => 'Boolean', doc => "Skip Creating new qc Files if they exist" , is_optional => 1, default => ""},
    ],
};

sub sub_command_sort_position { 12 }
sub help_brief {
    "Operate on germline capture model groups"                 
}
sub help_synopsis {
    return <<EOS
Operate on capture somatic model groups
EXAMPLE:    gmt capture germline-model-group-qc --group-id XXXX --output-dir --dbsnp-build
EOS
}
sub help_detail {
    return;
}

sub execute {
    my $self = shift;

    my $db_snp_build = $self->dbsnp_build;
    my $limit_snps_file = $self->limit_snps_file;
    my $data_source = $self->data_source;
    my $skip_if_output_present = $self->skip_if_output_present;
    my $summary_file = $self->summary_file;
    if ($self->summary_file) {
        $skip_if_output_present = 1;
        unless (open(ALL_MODELS,">$summary_file")) {
            die "Could not open input file '$summary_file' for reading";
        }
        print ALL_MODELS join("\t",qw(
            Dbsnp_Build
            Sample_id
            SNPsCalled
            WithGenotype
            MetMinDepth
            Reference
            RefMatch
            RefWasHet
            RefWasHom
            Variant
            VarMatch
            HomWasHet
            HetWasHom
            VarMismatch
            VarConcord
            RareHomConcord
            OverallConcord
            )) . "\n";
    }

    # Correct the reference build name to what the database recognizes
    my $reference;
    my $build_number;
    if( $db_snp_build <= 130) {
        $reference = 'reference';
        $build_number = 36;
    }
    else {
        $reference = 'GRCh37';
        $build_number = 37;
    }
    my %snp_limit_hash;
    if($self->limit_snps_file) {
        my $snp_input = new FileHandle ($self->limit_snps_file);
        unless($snp_input) {
            $self->error_message("Unable to open ".$self->limit_snps_file);
            return;
        }

        while (my $line = <$snp_input>) {
            chomp($line);
            my ($id) = split(/\t/, $line);
            $snp_limit_hash{$id}++;
        }
    }

    ## Get the models in each model group ##
    for my $model (map{$_->model}map{$_->model_bridges}Genome::ModelGroup->get($self->group_id))
    {
        my $model_id = $model->id;
        my $subject_name = $model->subject_name;
#        my $sample_name = $model->sample_name;
        $subject_name = "Model" . $model_id if(!$subject_name);
        if ($subject_name =~ m/Pooled/) {next;}
        if($model->last_succeeded_build_directory) {
            my $build = $model->last_succeeded_build;
            my $build_id = $build->id;
            my $last_build_dir = $model->last_succeeded_build_directory;
            my $bam_file = $build->whole_rmdup_bam_file;

            if($self->output_dir) {
                my $qc_dir = $self->output_dir . "/$subject_name/";
                mkdir($qc_dir);
                my $genofile = "$qc_dir/$subject_name.dbsnp$db_snp_build.genotype";
                my $qcfile = "$qc_dir/$subject_name.dbsnp$db_snp_build.qc";

                if ($skip_if_output_present && -s $genofile &&1&&1) { #&&1&&1 to make gedit show colors correctly after a -s check
                }
                elsif ($self->summary_file) {
                    die "You specified summary file but the script thinks there are unfinished qc files, please run this script to finish making qc files first\nReason: file $genofile does not exist as a non-zero file\n";
                }
                else {
                    open(GENOFILE, ">" . $genofile) or die "Can't open outfile: $!\n";

                    my $db_snp_info = GSC::SNP::DB::Info->get( snp_db_build => $db_snp_build );
                    my $type = 'reference';

                    # Get the sample
                    my $organism_sample = GSC::Organism::Sample->get( sample_name => $subject_name );

                    unless ($organism_sample) {
#                        $self->warning_message("failed to find sample $subject_name by external name, trying internal name...");
                        $organism_sample = GSC::Organism::Sample->get( full_name => $subject_name );
                        unless( defined $organism_sample ) {
                            warn "Skipping unrecognized sample name: $subject_name!\n";
                            next;
                        }
                    }

                    my @genotypes;
                    if( $data_source eq 'iscan' || $data_source eq 'internal') {
                        @genotypes = $organism_sample->get_genotype;
                    }
                    elsif( $data_source eq 'external') {
                        @genotypes = $organism_sample->get_external_genotype;
                    }

                    # Get all external genotypes for this sample
                    foreach my $genotype (@genotypes) {

                        #LSF: For Affymetrix, this will be the birdseed file.
                        my $ab_file = $genotype->get_genotype_file_ab;

                        # Get the data adapter (DataAdapter::GSGMFinalReport class object)
                        my $filter       = DataAdapter::Result::Filter::Nathan->new();
                        my $data_adapter = $genotype->get_genotype_data_adapter(
                            genome_build => $db_snp_info->genome_build,
                            snp_db_build => $db_snp_info->snp_db_build,
                            filter       => $filter,
#                             ( $type ? ( type => $type ) : () ),
                            ( $reference ? ( type => $reference ) : () ),
                        );

                        # Next if there is no genotype data.
                        next unless($data_adapter);

                        # Loop through the result row (DataAdapter::Result::GSGMFinalReport class object)
                        while ( my $result = $data_adapter->next_result ) {
                            if (!$self->limit_snps_file || defined $snp_limit_hash{$result->snp_name}) {
                                print GENOFILE join "\t",
                                ( $result->chromosome, $result->position, $result->alleles, $result->snp_name);
                                print GENOFILE "\n";
                            }
                        }
                    }
                    close(GENOFILE);
                }

                my $bsub = "bsub -N -M 4000000 -J $subject_name.dbsnp$db_snp_build.qc -o $qc_dir/$subject_name.dbsnp$db_snp_build.qc.out -e $qc_dir/$subject_name.dbsnp$db_snp_build.qc.err -R \"select[model!=Opteron250 && type==LINUX64 && mem>4000 && tmp>1000] rusage[mem=4000, tmp=1000]\"";
                my $cmd = $bsub." \'"."gmt analysis lane-qc compare-snps --genotype-file $genofile --bam-file $bam_file --output-file $qcfile --sample-name $subject_name --min-depth-het 20 --min-depth-hom 20 --flip-alleles 1 --verbose 1 --reference-build $build_number"."\'";
                if ($skip_if_output_present && -s $qcfile &&1&&1) { #&&1&&1 to make gedit show colors correctly after a -s check
                }
                elsif ($self->summary_file) {
                    die "You specified summary file but the script thinks there are unfinished qc files, please run this script to finish making qc files first\nReason: file $qcfile does not exist as a non-zero file\n";
                }
                else {
                    system("$cmd");
                }
                if ($self->summary_file) {
                    my $qc_input = new FileHandle ($qcfile);
                    my $qc_header = <$qc_input>;
                    my $qc_line = <$qc_input>;
                    chomp($qc_line);
                    print ALL_MODELS "$db_snp_build\t$qc_line\n";
                }
            }
        }

        UR::Context->commit() or die 'commit failed';
        UR::Context->clear_cache(dont_unload => ['Genome::ModelGroup', 'Genome::ModelGroupBridge']);
    }
    if ($self->summary_file) {
        close(ALL_MODELS);
    }
    return 1;
}

sub byChrPos
{
    my ($chr_a, $pos_a) = split(/\t/, $a);
    my ($chr_b, $pos_b) = split(/\t/, $b);

    $chr_a cmp $chr_b
        or
    $pos_a <=> $pos_b;
}
1;

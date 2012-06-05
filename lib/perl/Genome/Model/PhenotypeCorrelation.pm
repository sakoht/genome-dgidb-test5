package Genome::Model::PhenotypeCorrelation;

use strict;
use warnings;
use Genome;
use Math::Complex;

class Genome::Model::PhenotypeCorrelation {
    is => 'Genome::ModelDeprecated',
    doc => "genotype-phenotype correlation of a population group",
    has_param => [
        alignment_strategy => {
            is => "Text",
            is_many => 0,
            doc => "Strategy align sequence reads.",
        },
        snv_detection_strategy => {
            is => "Text",
            is_many => 0,
            is_optional =>1,
            doc => "Strategy to be used to detect snvs.",
        },
        indel_detection_strategy => {
            is => "Text",
            is_many => 0,
            is_optional =>1,
            doc => "Strategy to be used to detect indels.",
        },
        sv_detection_strategy => {
            is => "Text",
            is_many => 0,
            is_optional =>1,
            doc => "Strategy to be used to detect svs.",
        },
        cnv_detection_strategy => {
            is => "Text",
            is_many => 0,
            is_optional =>1,
            doc => "Strategy to be used to detect cnvs.",
        },
        roi_wingspan => {
            is => 'Text',
            doc => 'Area to include before and after ROI regions',
            is_optional => 1,
        },
        group_samples_for_genotyping_by => {
            is => "Text",
            is_many => 0,
            is_optional => 1,
            #default_value => 'each',
            valid_values => ['each', 'trio', 'all'],
            doc => "group samples together when genotyping, using this attribute, instead of examining genomes independently (use \"all\" or \"trio\")",
        },
        phenotype_analysis_strategy => {
            is => "Text",
            is_many => 0,
            is_optional =>1,
            valid_values => ['case-control','quantitative'],
            doc => "Strategy to use to look at phenotypes.",
        },
    ],
    has_input => [
        reference_sequence_build => {
            is => 'Genome::Model::Build::ReferenceSequence',
            doc => 'the reference sequence against which alignment and variant detection are done',
        },
        previous_variant_detection_results => {
            is => 'FilesystemPath',
            is_optional => 1,
            doc => 'path to a VCF of previous: skip variant detection and use this',
        },
        nomenclature => {
            is => 'Genome::Nomenclature',
            doc => 'nomenclature used to access clinical data'
        },
    ],
    has_optional_input => [
        roi_list => {
            is => 'Genome::FeatureList',
            is_optional => 1,
            doc => 'only variants in these regions will be included in the final VCF',
        },
        pedigree_file_path => {
            is => 'FilePath',
            doc => 'when supplied overrides the automatic lookup of familial relationships'
        },
        identify_cases_by => { 
            is => 'Text', 
            is_optional => 1,
            doc => 'the expression which matches "case" samples, typically by their attributes' 
        },
        identify_controls_by => { 
            is => 'Text', 
            is_optional => 1,
            doc => 'the expression which matches "control" samples, typically by their attributes' 
        },
    ],
};

sub help_synopsis_for_create_profile {
    my $self = shift;
    return <<"EOS"

  # quantitative

    genome processing-profile create phenotype-correlation \
      --name 'September 2011 Quantitative Population Phenotype Correlation' \
      --alignment-strategy              'instrument_data aligned to reference_sequence_build using bwa 0.5.9 [-q 5] then merged using picard 1.29 then deduplicated using picard 1.29' \
      --snv-detection-strategy          'samtools r599 filtered by snp-filter v1' \
      --indel-detection-strategy        'samtools r599 filtered by indel-filter v1' \
      --group-samples-for-genotyping-by 'race' \            # some (optional) phenotypic trait, or 'trio' or 'all'
      --phenotype-analysis-strategy     'quantitative' \    # or 'case-control'

    genome propulation-group define 'ASMS-cohort-WUTGI-2011' ASMS1 ASMS2 ASMS3 ASMS4

    genome model define phenotype-correlation \
        --name                      'ASMS-v1' \
        --subject                   'ASMS-cohort-WUTGI-2011' \
        --processing-profile        'September 2011 Quantitative Phenotype Correlation' \


  # case-control

    genome processing-profile create phenotype-correlation \
      --name 'September 2011 Case-Control Population Phenotype Correlation' \
      --alignment-strategy              'instrument_data aligned to reference_sequence_build using bwa 0.5.9 [-q 5] then merged using picard 1.29 then deduplicated using picard 1.29' \
      --snv-detection-strategy          'samtools r599 filtered by snp-filter v1' \
      --indel-detection-strategy        'samtools r599 filtered by indel-filter v1' \
      --group-samples-for-genotyping-by 'trio', \
      --roi_wingspan                    500 \
      --phenotype-analysis-strategy     'case-control'

    genome propulation-group define 'Ceft-Lip-cohort-WUTGI-2011' CL001 CL002 CL003

    genome model define phenotype-correlation \
        --name                  'Cleft-Lip-v1' \
        --subject               'Cleft-Lip-cohort-WUTGI-2011' \
        --processing-profile    'September 2011 Case-Control Phenotype Correlation' \
        --roi_list              'TEST_ROI' \
        --pedigree-file-path    /somedir/somesubdir/thisfamily.ped
        --identify-cases-by     'some_nomenclature.has_cleft_lip = "yes"' \
        --identify-controls-by  'some_nomenclature.has_cleft_lip = "no"' \


    # If you leave off the subject, it would find all patients matching the case/control logic
    # and make a population group called ASMS-v1-cohort automatically???


EOS
}

sub help_detail_for_create_profile {
    return <<EOS
  For a detailed explanation of how to write an alignmen strategy see:
    TBD

  For a detailed explanation of how to write a variant detection strategy, see:
    perldoc Genome::Model::Tools::DetectVariants2::Strategy;

  All builds will have a combined vcf in their variant detection directory.

EOS
}

sub help_manual_for_create_profile {
    return <<EOS
  Manual page content for this pipeline goes here.
EOS
}

sub __profile_errors__ {
    my $self = shift;
    my @errors;

    # this is currently broken --ssmith
    return;

    if ($self->alignment_strategy) {
        my $strategy = Genome::InstrumentData::Composite::Strategy->create(
            strategy => $self->strategy,
        );
        if ( not $strategy ) {
            push @errors, UR::Object::Tag->create(
                type => 'invalid',
                properties => [qw/ alignment_strategy /],
                desc => 'Failed to create validator for alignmnet strategy: '.$self->alignment_strategy,
            );
        }
        $strategy->dump_status_messages(1);
        if ( not $strategy->execute ) {
            push @errors, UR::Object::Tag->create(
                type => 'invalid',
                properties => [qw/ alignment_strategy /],
                desc => 'Failed to validate alignmnet strategy: '.$self->alignment_strategy,
            );
        }
    }
    for my $strategy ('snv','indel','sv','cnv') {
        my $method_name = $strategy . '_detection_strategy';
        if (my $strategy_text = $self->$method_name) {
            my $strat = Genome::Model::Tools::DetectVariants2::Strategy->get($strategy_text);
            push @errors,
                map {
                    UR::Object::Tag->create(
                        type => 'invalid',
                        properties => [$method_name],
                        desc => $_
                    )
                }
                $strat->__errors__;
        }
    }
    return @errors;
}

sub _resource_requirements_for_execute_build {
    return "-R 'select[mem>4000] rusage[mem=4000]' -M 4000000"
}

our $SHORTCUT_ALIGNMENT_QUERY = 0;
sub _execute_build {
    my ($self,$build) = @_;
    # TODO: remove this and replace with the workflow logic at the bottom when we have one.
    # Version 1 of this pipeline will run in a linear way only if the underlying samples have already
    # had independent alignment and variant detection completed in other models.

    warn "The logic for building this model is only partly functional!  Contact Human Genomics or put in an APIPE-support ticket..";

    #
    # the subject is a population group
    #

    my $population_group = $build->model->subject;
    $build->status_message("subject is " . $population_group->__display_name__);

    #
    # get the reference sequence
    #

    my $reference_build = $build->reference_sequence_build;
    $build->status_message("reference sequence build: " . $reference_build->__display_name__);
    
    my $reference_fasta = $reference_build->full_consensus_path('fa');
    unless(-e $reference_fasta){
        die $self->error_message("fasta file for reference build doesn't exist!");
    }
    $build->status_message("reference sequence fasta: " . $reference_fasta);

    #
    # get or create the vcf
    #

    my $multisample_vcf;
    my @builds;
    my @samples;
    if (! $build->previous_variant_detection_results) {
        # generate a multisample VCF

        #
        # get the subject (population group), the individual members and their samples
        #

        my @patients = $population_group->members();
        $build->status_message("found " . scalar(@patients) . " patients");

        @samples = $population_group->samples;
        $build->status_message("found " . scalar(@samples) . " samples");

        my @instdata_assn = $build->inputs(name => 'instrument_data');
        $build->status_message("found " . scalar(@instdata_assn) . " assignments for the current build");

        #my @instdata = Genome::InstrumentData->get(id => [ map { $_->value_id } @instdata_assn ]);
        my @instdata = map { $_->value } @instdata_assn;
        $build->status_message("found " . scalar(@instdata) . " instdata");

        #
        # get the alignment results for each sample
        # this will only work right now if the per-sample model has already run
        # once Tom's new alignment thing is in place, it would actually generate them in parallel
        #
        
        my $actually_gather_alignment_results = 1;

        my @per_sample_alignment_results;
        my @bams;
        
        if ($SHORTCUT_ALIGNMENT_QUERY) {
            # shortcut to speed testing
            @per_sample_alignment_results = Genome::SoftwareResult->get(
                [
                    '116553088',
                    '116553238',
                    '116553281'
                ]
            );
            
            @builds = Genome::Model::Build->get(
                [
                    '116552788',
                    '116552996',
                    '116553031'
                ]
            );

            @bams = (
            '/gscmnt/gc7001/info/build_merged_alignments/merged-alignment-blade13-4-10.gsc.wustl.edu-rlong-14103-116553088/116553088.bam',
            '/gscmnt/gc7001/info/build_merged_alignments/merged-alignment-blade13-4-10.gsc.wustl.edu-rlong-17210-116553238/116553238.bam',
            '/gscmnt/ams1152/info/build_merged_alignments/merged-alignment-blade13-4-7.gsc.wustl.edu-rlong-12110-116553281/116553281.bam'
            );
        }
        else {
            $self->status_message('Gathering alignments...');    
            my $overall_alignment_result = Genome::InstrumentData::Composite->get_or_create(
                inputs => {
                    instrument_data => \@instdata,
                    reference_sequence_build => $reference_build,
                },
                strategy => $self->alignment_strategy,
                log_directory => $build->log_directory,
            );

            # used by the updated DV2 API
            @per_sample_alignment_results = $overall_alignment_result->_merged_results;
            for my $r (@per_sample_alignment_results) {
                $r->add_user(label => 'uses', user => $build);
            }
            $self->status_message('Found ' . scalar(@per_sample_alignment_results) . ' per-sample alignmnet results.');

            # used directly by the merge tool until we switch to using the above directly
            @bams = $overall_alignment_result->bam_paths;
            $self->status_message('Found ' . scalar(@bams) . ' merged BAMs.');
            for my $bam (@bams){
                unless (-e $bam){
                    die $self->error_message("Bam file could not be reached at: ".$bam);
                }
            }

            # this is used by the old, non-DV2 code, but is also used by vcf2maf, 
            # which reliese on annotation having been run on the original samples
            @builds = $self->_get_builds(\@per_sample_alignment_results);
        
            my @ar_ids = map { $_->id } @per_sample_alignment_results;
            my @build_ids = map { $_->id } @builds; 
            print Data::Dumper::Dumper(\@ar_ids, \@build_ids, \@bams);
        }

        #
        # Detect Variants
        #
        # run the DV2 API to do variant detection as we do in somatic, but let it take in N BAMs
        # _internally_ it will (for the first pass):
        #  notice it's running on multiple BAMs
        #  get the single-BAM results
        #  merge them with joinx and make a combined VCF (tolerating the fact that per-bam variants are not VCF)
        #  run bamreadcount to fill-in the blanks
        #

        $self->status_message("Executing detect variants step");        

        my %params;
        $params{snv_detection_strategy} = $self->snv_detection_strategy if $self->snv_detection_strategy;
        $params{indel_detection_strategy} = $self->indel_detection_strategy if $self->indel_detection_strategy;
        $params{sv_detection_strategy} = $self->sv_detection_strategy if $self->sv_detection_strategy;
        $params{cnv_detection_strategy} = $self->cnv_detection_strategy if $self->cnv_detection_strategy;

        $params{reference_build_id} = $reference_build->id;

        my $output_dir = $build->data_directory."/variants";
        $params{output_directory} = $output_dir;

        # instead of setting {control_,}aligned_reads_{input,sample}
        # set alignment_results and control_alignment_results

        $params{alignment_results} = \@per_sample_alignment_results;
        $params{control_alignment_results} = [];
        $params{pedigree_file_path} = $build->pedigree_file_path;
        $params{roi_list} = $build->roi_list;
        $params{roi_wingspan} = $self->roi_wingspan;

        my $command = Genome::Model::Tools::DetectVariants2::Dispatcher->create(%params);
        unless ($command){
            die $self->error_message("Couldn't create detect variants dispatcher from params:\n".Data::Dumper::Dumper \%params);
        }

        my $rv = $command->execute;
        my $err = $@;
        unless ($rv){
            die $self->error_message("Failed to execute detect variants dispatcher(err:$@) with params:\n".Data::Dumper::Dumper \%params);
        }

        $self->status_message("detect variants command completed successfully");

        $multisample_vcf = $output_dir . '/snvs.merged.vcf.gz';

    }
    else {
        $multisample_vcf = $self->previous_variant_detection_results;
        $build->status_message("using pre-made VCF: $multisample_vcf");
        
        @samples = $population_group->samples;
        $build->status_message("found " . scalar(@samples) . " samples");
   
        # TODO: don't dependin on underlying builds, for polymutt etc there won't be any
        @builds = ();
    }

    #
    # Continue with analysis of the multisample_vcf
    #

    # dump pedigree data into a file

    # dump clinical data into a file

    # we'll figure out what to do about the analysis_strategy next...

    #get list of bams and load into tmp file named $bam_list
    #for exome set $target_region_set_name_bedfile to be all exons including splice sites, these files are maintained by cyriac
    ## Change roi away from gz file if necessary ##
    my $target_region_set_name_bedfile = $build->roi_list->file_path;


    if ($self->phenotype_analysis_strategy eq 'quantitative') { #unrelated individuals, quantitative -- ASMS-NFBC
#create a directory for results
        my $temp_path = Genome::Sys->create_temp_directory;
        $temp_path =~ s/\:/\\\:/g;

        my $maf_file = $self->vcf_to_maf($multisample_vcf,$temp_path,\@builds);
        $self->status_message("Merged Maf file located at: ".$maf_file);

        ## Build temp file for bam_list ##
        my ($tfh_bams,$bam_list) = Genome::Sys->create_temp_file;
        unless($tfh_bams) {
            die $self->error_message("Unable to create temporary file $!");
        }
        $bam_list =~ s/\:/\\\:/g;

        foreach my $build_object (@builds) {
            my $sample_name = $build_object->subject_name;
            my $bam_file = $build_object->whole_rmdup_bam_file;
            print $tfh_bams "$sample_name\t$bam_file\t$bam_file\n";
        }
        close($tfh_bams);


#Ran clinical-correlation:
#need clinical data file $clinical_data
#my $clinical_data_orig = '/gscmnt/gc2146/info/medseq/wschierd/crap_stuff_delete/Mock_Pheno_1kg.txt'; #comma or tab delim?

print "preparing clinical files\n";
        my %pheno_hash;
        my %attributes;
        my %is_it_binary;
        foreach my $sample (@samples) {
            my $sample_id = $sample->id;
            my $sample_name = $sample->name;
            my @sample_attributes = $sample->attributes_for_nomenclature($self->nomenclature);
            for my $attr (@sample_attributes) {
                $attributes{$attr->attribute_label} = $attr->nomenclature_field_type; #Right now the types are: integer, real, date, string, enumerated 
                $pheno_hash{$sample_name}{$attr->attribute_label} = $attr->attribute_value;
                $is_it_binary{$attr->attribute_label}{$attr->attribute_value}++;
            }
        }
        my @header_fields = sort keys %attributes;
        my $clinical_data = "$temp_path/Clinical_Data.txt";
        my $clinical_inFh = Genome::Sys->open_file_for_writing($clinical_data);
        print $clinical_inFh join("\t","Sample_name",@header_fields),"\n";

        for my $sample_name (sort keys %pheno_hash) {
            print $clinical_inFh join("\t","$sample_name",@{$pheno_hash{$sample_name}}{@header_fields}),"\n";
        }
        close($clinical_inFh);

        my $glm_model_file = '/gscmnt/sata424/info/medseq/Freimer-Boehnke/Final_Data_Set_20111213/3Center/MAF_File/glm-model-file.txt';
=cut
        my $glm_model_file = "$temp_path/Glm_Model_File.txt";
        my $glm_model_file_inFh = Genome::Sys->open_file_for_writing($glm_model_file);
#need a way to set this
#        my $covariates = "PC1+PC2+PC3+PC4+PC5";
        my $covariates = "NA";
        my @covariate_options = split(/\+/, $covariates);
        my $pheno_fh = new IO::File $clinical_data,"r";
        my $pheno_header = $pheno_fh->getline;
        chomp($pheno_header);
        close($pheno_fh);
        my @pheno_headers = split(/\t/, $pheno_header);
        my @pheno_minus_covariates;
        foreach my $phead (@pheno_headers) {
            my $match = 0;
            foreach my $cov (@covariate_options) {
                if ($phead eq $cov) {
                    $match = 1;
                }
            }
            unless ($match) {
                push(@pheno_minus_covariates,$phead);
            }
        }
        my $phenotype_list = join(",", @pheno_minus_covariates);

        print $glm_model_file_inFh "analysis_type\tclinical_data_trait_name\tvariant/gene_name\tcovariates\tmemo\n";
        foreach my $glm_attr (@header_fields) {
            my $data_type = $attributes{$glm_attr};
            my $analysis_data_type;
#            if (
            my $binary_assessment = scalar(keys %{$is_it_binary{$glm_attr}});
            if ($binary_assessment < 3 && ($data_type eq 'enumerated' || $data_type eq 'string')) {
                $analysis_data_type = 'B';
            }
            else {
                $analysis_data_type = 'Q';
            }
            print $glm_model_file_inFh "$analysis_data_type\t$glm_attr\tNA\t$covariates\tNA\n";
        }
        close($glm_model_file_inFh);
=cut

        #$name is project name or some other good identifier
        my $name = $self->name;
#smg bedfile $temp_path/smg_restricted_bed.bed
#starting bedfile $target_region_set_name_bedfile
        #my $variant_matrix_cmd = "gmt vcf vcf-to-variant-matrix --vcf-file $multisample_vcf --output-file $temp_path/variant_matrix.txt --project-name $name --matrix-genotype-version Numerical --bed-roi-file $target_region_set_name_bedfile --transpose";
        my $mutation_matrix = "$temp_path/$name"."_variant_matrix.txt";
        my $variant_matrix_cmd  = Genome::Model::Tools::Vcf::VcfToVariantMatrix->execute(
            vcf_file => $multisample_vcf,
            output_file => $mutation_matrix,
            project_name => $name,
            matrix_genotype_version => 'Numerical',
            bed_roi_file => $target_region_set_name_bedfile,
            transpose => 1,
        );
        unless($variant_matrix_cmd){
            die $self->error_message("Could not complete vcf to variant matrix conversion!");
        }

#system("cp $multisample_vcf /gscuser/wschierd/Deleteme/vcf.txt");
#system("cp $clinical_data /gscuser/wschierd/Deleteme/Clinicaldata.txt");
#system("cp $glm_model_file /gscuser/wschierd/Deleteme/glm_model_file.txt");
#system("cp $mutation_matrix /gscuser/wschierd/Deleteme/variant_matrix.txt");
#system("cp $target_region_set_name_bedfile /gscuser/wschierd/Deleteme/roi_bedfile.txt");
#system("cp $bam_list /gscuser/wschierd/Deleteme/bamlist.txt");
#system("cp $maf_file /gscuser/wschierd/Deleteme/maf.txt");

print "starting clinical correlation\n";
        #with above variant matrix forced in
#this file needs to be generated...somehow
        #my $clin_corr = "gmt music clinical-correlation --genetic-data-type variant --bam-list $bam_list --maf-file $maf_file --output-file $temp_path/clin_corr_result --categorical-clinical-data-file $clinical_data";
        my $clin_corr_cmd = Genome::Model::Tools::Music::ClinicalCorrelation->execute(
            genetic_data_type => "variant",
            bam_list => $bam_list,
            maf_file => $maf_file,
            output_file => "$temp_path/clin_corr_result",
            glm_model_file => $glm_model_file,
            glm_clinical_data_file => $clinical_data,
            input_clinical_correlation_matrix_file => $mutation_matrix,
            use_maf_in_glm => 1,
        );
        unless($clin_corr_cmd){
            die $self->error_message("Could not complete clinical correlation!");
        }

=cut
        my $fdr_cutoff = 0.05;
        #my $clin_corr_finish = "gmt germline finish-music-clinical-correlation --input-file $temp_path/clin_corr_result.categorical --output-file $temp_path/clin_corr_result_stats_FDR005.txt --output-pdf-image-file $temp_path/clin_corr_result_stats_FDR005.pdf --clinical-data-file $clinical_data --project-name $name --fdr-cutoff $fdr_cutoff --maf-file $maf_file";
        my $clin_corr_finish_cmd = Genome::Model::Tools::Germline::FinishMusicClinicalCorrelation->execute(
            input_file => "$temp_path/clin_corr_result.categorical",
            output_file => "$temp_path/clin_corr_result_stats_FDR005.txt",
            output_pdf_image_file => "$temp_path/clin_corr_result_stats_FDR005.pdf",
            clinical_data_file => $clinical_data,
            project_name => $name,
            fdr_cutoff => $fdr_cutoff,
            maf_file => $maf_file,
        );
        unless($clin_corr_finish_cmd){
            die $self->error_message("Could not complete clinical correlation finisher statistics!");
        }
=cut

print "starting annotation\n";
        my %annotation_hash;
        foreach my $build (@builds) {
            my $annotation_output_directory = $build->data_directory."/variants";
            my $annotation_file_per_sample = $annotation_output_directory."/filtered.variants.post_annotation";
            my $inFh_annotation = Genome::Sys->open_file_for_reading($annotation_file_per_sample);
            while (my $line = <$inFh_annotation>) {
            	chomp($line);
                my ($chromosome_name, $start, $stop, $reference, $variant, $mut_type, $gene_name, @everything_else) = split(/\t/, $line);
        	    #my $variant_name = $gene_name."_".$chromosome_name."_".$start."_".$stop."_".$reference."_".$variant;
        	    my $variant_name = $chromosome_name."_".$start."_".$reference."_".$variant; #this only matched vcf format for SNVs
            	$annotation_hash{$variant_name} = "$line";
            }
        }

        my $annotation_file_path = "$multisample_vcf.annotated";
        my $annotation_file_inFh = Genome::Sys->open_file_for_writing($annotation_file_path);

        foreach my $variant (sort keys %annotation_hash) {
        	print $annotation_file_inFh "$variant\t$annotation_hash{$variant}\n";
        }

        my $vep_annotation_file_path = "$multisample_vcf.VEP_annotated";

        my $ensembl_VEP_cmd = Genome::Db::Ensembl::Vep->execute(
            input_file => $multisample_vcf,
            output_file => $vep_annotation_file_path,
            format => 'vcf',
            condel => 'b',
            polyphen => 'b',
            sift => 'b',
            hgnc => 1,
            per_gene => 1,
        );
        unless($ensembl_VEP_cmd){
            die $self->error_message("Could not complete VEP annotation!");
        }

        my $vep_annotation_parsed_file_path = "$multisample_vcf.VEP_annotated.parsed";

        my $ensembl_VEP_parsed_cmd = Genome::Model::Tools::Annotate::ParseVep->execute(
            vep_input => $vep_annotation_file_path,
            output_file => $vep_annotation_parsed_file_path,
        );
        unless($ensembl_VEP_parsed_cmd){
            die $self->error_message("Could not complete VEP annotation parsing!");
        }

print "starting burden analysis\n";
        my $id = $build->id;
        my $testing_mode = 0;
        if ($id < 0) {
            $testing_mode = 1;
        }
        my $burden_temp_path_output = "$temp_path/BurdenAnalysisResults/";
        unless (-d $burden_temp_path_output) {
            system("mkdir $burden_temp_path_output");
        }
        my $burden_cmd = Genome::Model::Tools::Germline::BurdenAnalysis->execute(
            mutation_file => $mutation_matrix,
            glm_clinical_data_file => $clinical_data,
            VEP_annotation_file => $vep_annotation_parsed_file_path,
            project_name => $name,
            output_directory => $burden_temp_path_output,
            glm_model_file => $glm_model_file,
#            base_R_commands => '/gscuser/qzhang/gstat/burdentest/burdentest.R',
#            maf_cutoff => '0.01',
#            permutations => '10000',
#            trv_types => 'NMD_TRANSCRIPT,NON_SYNONYMOUS_CODING:NMD_TRANSCRIPT,NON_SYNONYMOUS_CODING,SPLICE_SITE:NMD_TRANSCRIPT,STOP_LOST:NON_SYNONYMOUS_CODING:NON_SYNONYMOUS_CODING,SPLICE_SITE:STOP_GAINED:STOP_GAINED,SPLICE_SITE',
#            select_phenotypes => $phenotype_list,
            testing_mode => $testing_mode,
        );
        unless($burden_cmd){
            die $self->error_message("Could not complete burden analysis!");
        }
=cut
#haplotype analysis

#haploview (per chr)
for my $chr (1..22,'X','Y') { #this needs to be set by the ROI or there will be empty files created where there are no variants on a chromosome (instead of chr, could be set per region)
    #split pedigree file up and specifically for haploview -- perhaps vcftools or plink can create this file for us?
#example script that messed around with this idea:
my $haplo_cmd = "perl /gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Vasily_to_Haploview_Format.pl"
#these need to be coming from the pedigree file, if we make one
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_file.txt
#per chromosome version of the above file
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr1.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr2.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr8.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr9.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr10.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr11.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr12.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr15.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr16.haps
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_filechr19.haps
    my $hap_infile = "$temp_path/$name.haploview_filechr$chr.haps";

#variant name and position information can be fed into haploview somehow
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/1941samples_washuvasilyoverlap_haploview_file_markers.txt

    my $hap_outfile = "$temp_path/$name.haploview_filechr$chr.output";
    my $hapview_cmd = "haploview -nogui -out $hap_outfile -haps $hap_infile -png";
    my $haploview_png = $hap_outfile.".LD.PNG";
}

#plot genotype distributions by clinical variable
my $clinical_variable_distribution_cmd = "perl /gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Vasily_plus_Phenotype.pl"
#example outputs:
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_bmires.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_crpres.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_diares.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_glures.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_hdlres.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_insres.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_ldlres.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_sysres.pdf
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/Data_Freeze_20110207/Data_Freeze_Samples/Data_Sharing_Exercise/WashU_Vasily_Combined/Genotypes_tgres.pdf


#find the significant gene pathways within an ROI:
#perl /gscmnt/sata424/info/medseq/Freimer-Boehnke/79_gene_pathways/groupGenes.pl 
#Raw output:
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/79_gene_pathways/GenePathways.txt 
#Matrix:
#/gscmnt/sata424/info/medseq/Freimer-Boehnke/79_gene_pathways/GeneConnectome.txt
=cut

    }
    elsif ($self->phenotype_analysis_strategy eq 'case-control') { #unrelated individuals, case-control -- MRSA
#create a directory for results
        my $temp_path = Genome::Sys->create_temp_directory;
        $temp_path =~ s/\:/\\\:/g;

        my $maf_file = vcf_to_maf($multisample_vcf,$temp_path,\@builds);
        $self->status_message("Merged Maf file located at: ".$maf_file);

        ## Build temp file for bam_list ##
        my ($tfh_bams,$bam_list) = Genome::Sys->create_temp_file;
        unless($tfh_bams) {
            die $self->error_message("Unable to create temporary file $!");
        }
        $bam_list =~ s/\:/\\\:/g;

        ## Build temp file for bam_list ##
        my ($tfh_cmds,$cmd_list) = Genome::Sys->create_temp_file;
        unless($tfh_cmds) {
            die $self->error_message("Unable to create temporary file $!");
        }
        $cmd_list =~ s/\:/\\\:/g;

        foreach $build (@builds) {
            my $sample_name = $build->subject_name;
            my $bam_file = $build->whole_rmdup_bam_file;
            print $tfh_bams "$sample_name\t$bam_file\t$bam_file\t$bam_file\n";
        }
        close($tfh_bams);


#start workflow to find significantly mutated genes in our set:
        
        my $user = $ENV{USER};
        #my $bmr_cmd = "gmt music bmr calc-covg --bam-list $bam_list --output-dir $temp_path --reference-sequence $reference_fasta --roi-file $target_region_set_name_bedfile --cmd-prefix bsub --cmd-list-file $cmd_list";
        my $bmr_cmd = Genome::Model::Tools::Music::Bmr::CalcCovg->execute(
            bam_list => $bam_list,
            output_dir => $temp_path,
            reference_sequence => $reference_fasta,
            roi_file => $target_region_set_name_bedfile,
            cmd_prefix => "",
            cmd_list_file => $cmd_list,
        );
        unless($bmr_cmd){
            die $self->error_message("Could not complete bmr step 1!");
        }

        #Submitted all the jobs in cmd_list_file to LSF:
        my $submit_cmd = "bash $cmd_list";
        system($submit_cmd);

#sleep(60);
#need to wait for the above to be done......

        #After the parallelized commands are all done, merged the individual results using the same tool that generated the commands: - MUST KNOW ABOVE STEP IS COMPLETE
        #my $bmr_step2_cmd = "gmt music bmr calc-covg --bam-list $bam_list --output-dir $temp_path --reference-sequence $reference_fasta --roi-file $target_region_set_name_bedfile";
        my $bmr_step2_cmd = Genome::Model::Tools::Music::Bmr::CalcCovg->execute(
            bam_list => $bam_list,
            output_dir => $temp_path,
            reference_sequence => $reference_fasta,
            roi_file => $target_region_set_name_bedfile,
        );
        unless($bmr_step2_cmd){
            die $self->error_message("Could not complete bmr step 2!");
        }


        #Calculated mutation rates:
        #my $bmr_step3_cmd = "gmt music bmr calc-bmr --bam-list $bam_list --output-dir $temp_path --reference-sequence $reference_fasta --roi-file $target_region_set_name_bedfile --maf-file $maf_file --show-skipped"; #show skipped doesn't work in workflow context
        my $bmr_step3_cmd = Genome::Model::Tools::Music::Bmr::CalcBmr->execute(
            bam_list => $bam_list,
            output_dir => $temp_path,
            reference_sequence => $reference_fasta,
            roi_file => $target_region_set_name_bedfile,
            maf_file => $maf_file,
            skip_non_coding => 0,
            skip_silent => 0,
#case-control is 2 groups?  --bmr-groups
        );
        unless($bmr_step3_cmd){
            die $self->error_message("Could not complete bmr step 2!");
        }

#system("cp $maf_file /gscmnt/gc2146/info/medseq/wschierd/crap_stuff_delete/maf_file.maf");
#system("cp $bam_list /gscmnt/gc2146/info/medseq/wschierd/crap_stuff_delete/bam_list.txt");
#system("cp $temp_path/* /gscmnt/gc2146/info/medseq/wschierd/crap_stuff_delete/");

        #Ran SMG test:
        #The smg test limits its --output-file to a --max-fdr cutoff. A full list of genes is always stored separately next to the output with prefix "_detailed".
        my $fdr_cutoff = 0.2; #0.2 is the default -- For every gene, if the FDR for at least 2 of theses test are less than $fdr_cutoff, it is considered as an SMG.
        #my $smg_cmd = "gmt music smg --gene-mr-file $temp_path/gene_mrs --output-file $temp_path/smgs --max-fdr $fdr_cutoff";
#        my $smg_cmd = Genome::Model::Tools::Music::Smg->execute(
#            gene_mr_file => "$temp_path/gene_mrs",
#            output_file => "$temp_path/smgs",
#            max_fdr => $fdr_cutoff,
#        );
#        unless($smg_cmd){
#            system("cp $temp_path/* /gscmnt/gc2146/info/medseq/wschierd/crap_stuff_delete/");
#            die $self->error_message("Could not complete smg test!");
#        }

        #my $smg_maf_cmd = "gmt capture restrict-maf-to-smgs --maf-file $maf_file --output-file $temp_path/smg_restricted_maf.maf --output-bed-smgs $temp_path/smg_restricted_bed.bed --smg-file $temp_path/smgs";
#        my $smg_maf_cmd = Genome::Model::Tools::Capture::RestrictMafToSmgs->execute(
#            output_file => "$temp_path/smg_restricted_maf.maf",
#            smg_file => "$temp_path/smgs",
#            maf_file => $maf_file,
#            output_bed_smgs => "$temp_path/smg_restricted_bed.bed",
#        );
#        unless($smg_maf_cmd){
#            die $self->error_message("Could not complete smg test!");
#        }

#get some pathway information, not used now but we could technically choose to run only genes from certain pathways
        #Ran PathScan on the KEGG DB (Larger DBs take longer):
        #get KEGG DB FILE $kegg_db
#build36 kegg_db 
my $kegg_db = '/gscmnt/gc2108/info/medseq/ckandoth/music/brc_input/pathway_dbs/KEGG_120910';
        #my $pathscan_cmd = "gmt music path-scan --bam-list $bam_list --gene-covg-dir $temp_path/gene_covgs/ --maf-file $maf_file --output-file $temp_path/sm_pathways_kegg --pathway-file $kegg_db --bmr 8.9E-07 --min-mut-genes-per-path 2";
        my $pathscan_cmd = Genome::Model::Tools::Music::PathScan->execute(
            bam_list => $bam_list,
            gene_covg_dir => "$temp_path/gene_covgs/",
            maf_file => $maf_file,
            output_file => "$temp_path/sm_pathways_kegg",
            pathway_file => $kegg_db,
            bmr => "8.9E-07",
            min_mut_genes_per_path => "2",
        );
        unless($pathscan_cmd){
            die $self->error_message("Could not complete pathscan!");
        }

        #Ran COSMIC-OMIM tool:
        #my $cosmic_cmd = "gmt music cosmic-omim --maf-file $maf_file --output-file $maf_file.cosmic_omim";
        my $cosmic_cmd = Genome::Model::Tools::Music::CosmicOmim->execute(
            maf_file => $maf_file,
            output_file => "$maf_file.cosmic_omim",
        );
        unless($cosmic_cmd){
            die $self->error_message("Could not complete cosmic test!");
        }

        #Ran Pfam tool:
        #my $pfam_cmd = "gmt music pfam --maf-file $maf_file --output-file $maf_file.pfam";
        my $pfam_cmd = Genome::Model::Tools::Music::Pfam->execute(
            maf_file => $maf_file,
            output_file => "$maf_file.pfam",
        );
        unless($pfam_cmd){
            die $self->error_message("Could not complete pfam test!");
        }

        #Ran Proximity tool:
        #my $proximity_cmd = "gmt music proximity --maf-file $maf_file --reference-sequence $reference_fasta --output-file $temp_path/variant_proximity";
        my $proximity_cmd = Genome::Model::Tools::Music::Proximity->execute(
            maf_file => $maf_file,
            output_dir => $temp_path,
        );
        unless($proximity_cmd){
            die $self->error_message("Could not complete proximity test!");
        }

        #Ran mutation-relation:
        my $permutations = 1000; #the default is 100, but cyriac and yanwen used either 1000 or 10000. Not sure of the reasoning behind those choices.
        #my $mutrel_cmd = "gmt music mutation-relation --bam-list $bam_list --maf-file $maf_file --output-file $temp_path/mutation_relations.csv --permutations $permutations --gene-list $temp_path/smgs";
#        my $mutrel_cmd = Genome::Model::Tools::Music::MutationRelation->execute(
#            bam_list => $bam_list,
#            maf_file => $maf_file,
#            output_file => "$temp_path/mutation_relations.csv",
#            permutations => $permutations,
#            gene_list => "$temp_path/smgs",
#        );
#        unless($mutrel_cmd){
#            die $self->error_message("Could not complete mutrel test!");
#        }

#instead of pathways, use smg test to limit maf file input into mutation relations $maf_file_smg -- no script for this step yet
#The FDR filtered SMG list can be used as input to "gmt music mutation-relation" thru --gene-list, so it limits its tests to SMGs only. No need to make a new MAF. Something similar could be implemented for clinical-correlation.

#Ran clinical-correlation:
#need clinical data file $clinical_data
#my $clinical_data_orig = '/gscmnt/gc2146/info/medseq/wschierd/crap_stuff_delete/Mock_Pheno_1kg.txt';
print "preparing clinical files\n";
        my %pheno_hash;
        my %attributes;
        my %is_it_binary;
        foreach my $sample (@samples) {
            my $sample_id = $sample->id;
            my $sample_name = $sample->name;
            my @sample_attributes = $sample->attributes_for_nomenclature($self->nomenclature);
            for my $attr (@sample_attributes) {
                $attributes{$attr->attribute_label} = $attr->nomenclature_field_type; #Right now the types are: integer, real, date, string, enumerated 
                $pheno_hash{$sample_name}{$attr->attribute_label} = $attr->attribute_value;
                $is_it_binary{$attr->attribute_label}{$attr->attribute_value}++;
            }
        }
        my @header_fields = sort keys %attributes;
        my $clinical_data = "$temp_path/Clinical_Data.txt";
        my $clinical_inFh = Genome::Sys->open_file_for_writing($clinical_data);
        print $clinical_inFh join("\t","Sample_name",@header_fields),"\n";

        for my $sample_name (sort keys %pheno_hash) {
            print $clinical_inFh join("\t","$sample_name",@{$pheno_hash{$sample_name}}{@header_fields}),"\n";
        }
        close($clinical_inFh);

        my $glm_model_file = '/gscmnt/sata424/info/medseq/Freimer-Boehnke/Final_Data_Set_20111213/3Center/MAF_File/glm-model-file.txt';
=cut
        my $glm_model_file = "$temp_path/Glm_Model_File.txt";
        my $glm_model_file_inFh = Genome::Sys->open_file_for_writing($glm_model_file);
#need a way to set this
#        my $covariates = "PC1+PC2+PC3+PC4+PC5";
        my $covariates = "NA";

        my @covariate_options = split(/\+/, $covariates);
        my $pheno_fh = new IO::File $clinical_data,"r";
        my $pheno_header = $pheno_fh->getline;
        chomp($pheno_header);
        close($pheno_fh);
        my @pheno_headers = split(/\t/, $pheno_header);
        my @pheno_minus_covariates;
        foreach my $phead (@pheno_headers) {
            my $match = 0;
            foreach my $cov (@covariate_options) {
                if ($phead eq $cov) {
                    $match = 1;
                }
            }
            unless ($match) {
                push(@pheno_minus_covariates,$phead);
            }
        }
        my $phenotype_list = join(",", @pheno_minus_covariates);

        print $glm_model_file_inFh "analysis_type\tclinical_data_trait_name\tvariant/gene_name\tcovariates\tmemo\n";
        foreach my $glm_attr (@header_fields) {
            my $data_type = $attributes{$glm_attr};
            my $analysis_data_type;
#            if (
            my $binary_assessment = scalar(keys %{$is_it_binary{$glm_attr}});
            if ($binary_assessment < 3 && ($data_type eq 'enumerated' || $data_type eq 'string')) {
                $analysis_data_type = 'B';
            }
            else {
                $analysis_data_type = 'Q';
            }
            print $glm_model_file_inFh "$analysis_data_type\t$glm_attr\tNA\t$covariates\tNA\n";
        }
        close($glm_model_file_inFh);
=cut

#example: /gscmnt/sata809/info/medseq/MRSA/analysis/Sureselect_49_Exomes_Germline/music/input/sample_phenotypes2.csv
#$name is project name or some other good identifier
my $name = $self->name;
#smg bedfile $temp_path/smg_restricted_bed.bed
#starting bedfile $target_region_set_name_bedfile
        #my $variant_matrix_cmd = "gmt vcf vcf-to-variant-matrix --vcf-file $multisample_vcf --output-file $temp_path/variant_matrix.txt --project-name $name --matrix-genotype-version Numerical --bed-roi-file $target_region_set_name_bedfile --transpose";
        my $mutation_matrix = "$temp_path/$name"."_variant_matrix.txt";
        my $variant_matrix_cmd  = Genome::Model::Tools::Vcf::VcfToVariantMatrix->execute(
            vcf_file => $multisample_vcf,
            output_file => $mutation_matrix,
            project_name => $name,
            matrix_genotype_version => 'Numerical',
            bed_roi_file => $target_region_set_name_bedfile,
            transpose => 1,
        );
        unless($variant_matrix_cmd){
            die $self->error_message("Could not complete vcf to variant matrix conversion!");
        }

        #with above variant matrix forced in
#this file needs to be generated...somehow
        #my $clin_corr = "gmt music clinical-correlation --genetic-data-type variant --bam-list $bam_list --maf-file $maf_file --output-file $temp_path/clin_corr_result --categorical-clinical-data-file $clinical_data";
        my $clin_corr_cmd = Genome::Model::Tools::Music::ClinicalCorrelation->execute(
            genetic_data_type => "variant",
            bam_list => $bam_list,
            maf_file => $maf_file,
            output_file => "$temp_path/clin_corr_result",
            glm_model_file => $glm_model_file,
            glm_clinical_data_file => $clinical_data,
            input_clinical_correlation_matrix_file => $mutation_matrix,
            use_maf_in_glm => 1,
        );
        unless($clin_corr_cmd){
            die $self->error_message("Could not complete clinical correlation!");
        }

=cut
        $fdr_cutoff = 0.05;
        #my $clin_corr_finish = "gmt germline finish-music-clinical-correlation --input-file $temp_path/clin_corr_result.categorical --output-file $temp_path/clin_corr_result_stats_FDR005.txt --output-pdf-image-file $temp_path/clin_corr_result_stats_FDR005.pdf --clinical-data-file $clinical_data --project-name $name --fdr-cutoff $fdr_cutoff --maf-file $maf_file";
        my $clin_corr_finish_cmd = Genome::Model::Tools::Germline::FinishMusicClinicalCorrelation->execute(
            input_file => "$temp_path/clin_corr_result.categorical",
            output_file => "$temp_path/clin_corr_result_stats_FDR005.txt",
            output_pdf_image_file => "$temp_path/clin_corr_result_stats_FDR005.pdf",
            clinical_data_file => $clinical_data,
            project_name => $name,
            fdr_cutoff => $fdr_cutoff,
            maf_file => $maf_file,
        );
        unless($clin_corr_finish_cmd){
            die $self->error_message("Could not complete clinical correlation finisher statistics!");
        }
=cut
#find sites that are important and also of a type we like (such as all Nonsynonymous/splice_site mutations in regions of interest unique to cases vs controls
#/gscmnt/sata809/info/medseq/MRSA/analysis/Sureselect_49_Exomes_Germline/causal_variants/pull_causal_variants.pl

print "starting annotation\n";
        my %annotation_hash;
        foreach my $build (@builds) {
            my $annotation_output_directory = $build->data_directory."/variants";
            my $annotation_file_per_sample = $annotation_output_directory."/filtered.variants.post_annotation";
            my $inFh_annotation = Genome::Sys->open_file_for_reading($annotation_file_per_sample);
            while (my $line = <$inFh_annotation>) {
            	chomp($line);
                my ($chromosome_name, $start, $stop, $reference, $variant, $mut_type, $gene_name, @everything_else) = split(/\t/, $line);
        	    #my $variant_name = $gene_name."_".$chromosome_name."_".$start."_".$stop."_".$reference."_".$variant;
        	    my $variant_name = $chromosome_name."_".$start."_".$reference."_".$variant; #this only matched vcf format for SNVs
            	$annotation_hash{$variant_name} = "$line";
            }
        }

        my $annotation_file_path = "$multisample_vcf.annotated";
        my $annotation_file_inFh = Genome::Sys->open_file_for_writing($annotation_file_path);

        foreach my $variant (sort keys %annotation_hash) {
        	print $annotation_file_inFh "$variant\t$annotation_hash{$variant}\n";
        }

        my $vep_annotation_file_path = "$multisample_vcf.VEP_annotated";

        my $ensembl_VEP_cmd = Genome::Db::Ensembl::Vep->execute(
            input_file => $multisample_vcf,
            output_file => $vep_annotation_file_path,
            format => 'vcf',
            condel => 'b',
            polyphen => 'b',
            sift => 'b',
            hgnc => 1,
            per_gene => 1,
        );
        unless($ensembl_VEP_cmd){
            die $self->error_message("Could not complete VEP annotation!");
        }

        my $vep_annotation_parsed_file_path = "$multisample_vcf.VEP_annotated.parsed";

        my $ensembl_VEP_parsed_cmd = Genome::Model::Tools::Annotate::ParseVep->execute(
            vep_input => $vep_annotation_file_path,
            output_file => $vep_annotation_parsed_file_path,
        );
        unless($ensembl_VEP_parsed_cmd){
            die $self->error_message("Could not complete VEP annotation parsing!");
        }

print "starting burden analysis\n";
        my $id = $build->id;
        my $testing_mode = 0;
        if ($id < 0) {
            $testing_mode = 1;
        }
        my $burden_temp_path_output = "$temp_path/BurdenAnalysisResults/";
        unless (-d $burden_temp_path_output) {
            system("mkdir $burden_temp_path_output");
        }
        my $burden_cmd = Genome::Model::Tools::Germline::BurdenAnalysis->execute(
            mutation_file => $mutation_matrix,
            glm_clinical_data_file => $clinical_data,
            VEP_annotation_file => $vep_annotation_parsed_file_path,
            project_name => $name,
            output_directory => $burden_temp_path_output,
            glm_model_file => $glm_model_file,
#            base_R_commands => '/gscuser/qzhang/gstat/burdentest/burdentest.R',
#            maf_cutoff => '0.01',
#            permutations => '10000',
#            trv_types => 'NMD_TRANSCRIPT,NON_SYNONYMOUS_CODING:NMD_TRANSCRIPT,NON_SYNONYMOUS_CODING,SPLICE_SITE:NMD_TRANSCRIPT,STOP_LOST:NON_SYNONYMOUS_CODING:NON_SYNONYMOUS_CODING,SPLICE_SITE:STOP_GAINED:STOP_GAINED,SPLICE_SITE',
#            select_phenotypes => $phenotype_list,
            testing_mode => $testing_mode,
        );
        unless($burden_cmd){
            die $self->error_message("Could not complete burden analysis!");
        }
    }

    return 1;
}

sub vcf_to_maf {
    # assume that the vcf is passed in as $multisample_vcf
    my $self = shift;
    my $multisample_vcf = shift;
    my $temp_path = shift;
    my $build_ref = shift;
    my @builds = @{$build_ref};
    my $single_sample_dir = "$temp_path/";
    #change vcf -> maf here, which also needs annotation files
    #make $maf_file -- might need one with everything and one that doesnt have silent variants in it

    #my $vcf_line = `grep -v "##" $multisample_vcf | head -n 1`;
    #chomp($vcf_line);
    #my ($chr, $pos, $id, $ref, $alt, $qual, $filter, $info, $format, @sample_names) = split(/\t/, $vcf_line);
    
#    my $vcf_split_cmd = "gmt vcf vcf-split-samples --vcf-input $multisample_vcf --output-dir $single_sample_dir";
#    print "$vcf_split_cmd\n";
#    system($vcf_split_cmd);
    my $vcf_split_cmd = Genome::Model::Tools::Vcf::VcfSplitSamples->execute(
        vcf_input => $multisample_vcf,
        output_dir => $single_sample_dir,
    );
    unless($vcf_split_cmd){
        die $self->error_message("Could not complete vcf splitting!");
    }

    print "single_sample_dir located at: ".$single_sample_dir."\n";

    my $maf_header;
    my $maf_maker_cmd = "cat";
    foreach my $build (@builds) {
        my $sample_id = $build->subject_name;
        my $annotation_output_directory = $build->data_directory."/variants";
        my $annotation_file_per_sample = $annotation_output_directory."/filtered.variants.post_annotation"; #needs to get some sort of single-sample annotation file from the build or maybe there is a unified annotation file to use?

#        my $vcf_cmd = "gmt vcf convert maf vcf-2-maf --vcf-file $single_sample_dir/$sample_id.vcf --annotation-file $annotation_file_per_sample --output-file $single_sample_dir/$sample_id.maf";
#        print "$vcf_cmd\n";
#        system($vcf_cmd);
        my $vcf_cmd = Genome::Model::Tools::Vcf::Convert::Maf::Vcf2Maf->execute(
            vcf_file => "$single_sample_dir/$sample_id.vcf",
            annotation_file => $annotation_file_per_sample,
            output_file => "$single_sample_dir/$sample_id.maf",
        );
        unless($vcf_cmd){
            die $self->error_message("Could not complete vcf to maf creation!");
        }
        $maf_maker_cmd .= " $single_sample_dir/$sample_id.maf";
    }
    my $maf_sample_id = $builds[0]->subject_name;
    $maf_maker_cmd .= " | grep -v \"Hugo_Symbol\" > $single_sample_dir/All_Samples_noheader.maf";
    system($maf_maker_cmd);
    my $final_maf = "$single_sample_dir/All_Samples.maf";
    my $final_maf_maker_cmd = "head -n1 $single_sample_dir/$maf_sample_id.maf | cat - $single_sample_dir/All_Samples_noheader.maf > $final_maf";
    system($final_maf_maker_cmd);
    return $final_maf;
}

sub _get_builds {
    my $self = shift;
    my $results = shift;
    my @results = @{$results};
    my @builds;
    for my $result (@results) {
        my @users_who_are_builds = grep { $_->user_class_name =~ m/Genome\:\:Model\:\:Build\:\:ReferenceAlignment/ } $result->users;
        push @builds, Genome::Model::Build->get($users_who_are_builds[0]->user_id);
    }
    return @builds;
}


sub _validate_build {
    # this is where we sanity check things like inputs making sense before actually building
    my $self = shift;
    my $dir = $self->data_directory;

    my @errors;
    unless (1) {
        my $e = $self->error_message("Something is wrong!");
        push @errors, $e;
    }

    if (@errors) {
        return;
    }
    else {
        return 1;
    }
}

1;

__END__

# TODO: replace the above _execute_build with an actual workflow

sub _resolve_workflow_for_build {
    my $self = shift;
    my $build = shift;

    my $operation = Workflow::Operation->create_from_xml(__FILE__ . '.xml');

    my $log_directory = $build->log_directory;
    $operation->log_dir($log_directory);

    #I think this ideally should be handled
    $operation->name($build->workflow_name);

    return $operation;
}

sub _map_workflow_inputs {
    my $self = shift;
    my $build = shift;

    my @inputs = ();

    #### This is old code from the somatic variation pipeline, replace with phenotype correlation params/inputs! #####

    # Verify the somatic model
    my $model = $build->model;

    unless ($model) {
        $self->error_message("Failed to get a model for this build!");
        die $self->error_message;
    }

    my $tumor_build = $build->tumor_build;
    my $normal_build = $build->normal_build;

    unless ($tumor_build) {
        $self->error_message("Failed to get a tumor_build associated with this somatic capture build!");
        die $self->error_message;
    }

    unless ($normal_build) {
        $self->error_message("Failed to get a normal_build associated with this somatic capture build!");
        die $self->error_message;
    }

    my $data_directory = $build->data_directory;
    unless ($data_directory) {
        $self->error_message("Failed to get a data_directory for this build!");
        die $self->error_message;
    }

    my $tumor_bam = $tumor_build->whole_rmdup_bam_file;
    unless (-e $tumor_bam) {
        $self->error_message("Tumor bam file $tumor_bam does not exist!");
        die $self->error_message;
    }

    my $normal_bam = $normal_build->whole_rmdup_bam_file;
    unless (-e $normal_bam) {
        $self->error_message("Normal bam file $normal_bam does not exist!");
        die $self->error_message;
    }

    push @inputs, build_id => $build->id;

    return @inputs;
}

1;

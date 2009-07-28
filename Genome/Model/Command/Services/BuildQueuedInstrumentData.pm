package Genome::Model::Command::Services::BuildQueuedInstrumentData;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Services::BuildQueuedInstrumentData {
    is => 'Command',
    has => [
        test => {
            is => 'String',
            doc => "This parameter, if set true, will only process pses with negative id's, allowing your test to complete in a reasonable time frame.",
            is_optional => 1,
            default => 0,
        }
    ],
};


sub help_brief {
    'Find all QueueInstrumentDataForGenomeModeling PSEs, create appropriate models, assign instrument data, and finally trigger Build on the model'
}

sub help_synopsis {
    return <<'EOS'
EOS
}

sub help_detail {
    return <<EOS
EOS
}

sub execute {
    my $self = shift;

    my $ps = GSC::ProcessStep->get(process_to => 'queue instrument data for genome modeling');
    my @pses = GSC::PSE->get(
                             ps_id => $ps->ps_id,
                             pse_status => 'inprogress',
                         );
    my %model_ids;
    PSE: foreach my $pse (@pses) {

          my $pse_id = $pse->id();
          
          if ($self->test){
              next if $pse_id > 0;
          }

          
          my ($instrument_data_type)      = $pse->added_param('instrument_data_type');
          my ($instrument_data_id)        = $pse->added_param('instrument_data_id');
          my ($subject_type)              = $pse->added_param('subject_type');
          my ($subject_name)              = $pse->added_param('subject_name');
          my ($sample_name)               = $pse->added_param('sample_name');
          my ($library_name)              = $pse->added_param('library_name');
          my ($research_project_name)     = $pse->added_param('research_project_name');
          
          my @processing_profile_names    = $pse->added_param('processing_profile_name');
          
          unless (@processing_profile_names) {
              $self->error_message("no processing profiles for instrument data '$instrument_data_id' PSE '$pse_id'");
              $pse->pse_status("completed");
              next PSE;
          }
          
          unless (
              ($instrument_data_type =~ /sanger/i) ||
              ($instrument_data_type =~ /solexa/i) ||
              ($instrument_data_type =~ /454/)
          ) { 
              next PSE; 
          }
          
          if ($instrument_data_type =~ /sanger/i) {
              
              my $pse      = GSC::PSE::AnalyzeTraces->get($instrument_data_id);
              
              unless (defined($pse)) {
                  $self->error_message("failed to fetch pse for sanger instrument data with id '$instrument_data_id'");
                  next PSE;
              }
              
              my $run_name = $pse->run_name();
              
              unless (defined($run_name)) {
                  $self->error_message("failed to get a run_name for sanger instrument data with id '$instrument_data_id'");
                  next PSE;
              }                                                                     
              
              $instrument_data_id = $run_name;
              
          }
          
          my $genome_instrument_data = Genome::InstrumentData->get(id => $instrument_data_id);
          
          unless (defined($genome_instrument_data)) {
              
              warn "Failed to get a Genome::InstrumentData via id '$instrument_data_id' pse_id '$pse_id'";
              next PSE;
              
          }
          if ($instrument_data_type =~ /solexa/i) {

              my @bwa_pp_1 = grep { $_ eq 'bwa0.4.9 28 seed -R 2 4 threads samtools r320wu1' } @processing_profile_names;

              unless (@bwa_pp_1 > 0) {
                  push @processing_profile_names, 'bwa0.4.9 and samtools r320wu1'; 
              }

              my @maq_pp = grep { $_ eq 'maq 0.7.1' } @processing_profile_names;

              unless (@maq_pp > 0) {
                  push @processing_profile_names, 'maq 0.7.1';
              }

          }
          
        my @process_errors;
        PP: foreach my $processing_profile_name (@processing_profile_names) {
              
              my $auto_build = 1;

              unless (defined($processing_profile_name) && ($processing_profile_name =~ /\S+/)) {
                  $self->error_message("got garbage processing profile name for instrument data '$instrument_data_id' PSE '$pse_id'");
                  push @process_errors, $self->error_message;
                  next PP;
              }
              
              my $pp = Genome::ProcessingProfile->get(name => $processing_profile_name);
              
              unless ($pp) {
                  $self->error_message("Failed to get processing profile '$processing_profile_name' for inprogress pse ". $pse->pse_id);
                  push @process_errors, $self->error_message;
                  next PP;
              }
            
              # Don't want to auto-build these...
              if (
                  ($processing_profile_name eq 'Maq 0.7.1 and Samtools r320wu1')
                  ||
                  ($processing_profile_name eq 'maq 0.7.1')
                  ||
                  ($pp->id() == 2128324)  
                  ||
                  ($pp->id() == 2036054)
                 ) {
                  $auto_build = 0;
              }
                                              
              my @models  = Genome::Model->get(
                  subject_name          => $subject_name,
                  processing_profile_id => $pp->id,
                  auto_assign_inst_data => 1,
              );
              
              # For Solexa Instrument Data, we don't want to (automagically) assign capture and non-capture data to the same model.
              if ($instrument_data_type =~ /solexa/i) {
                  
                  my $capture_target = $genome_instrument_data->target_region_set_name();
                  
                  my @compatible_models = ( );
                
                  foreach my $model (@models) {
                    
                      my $model_is_compatible = 0;

                      # What about models with no already assigned instrument data?  To assign or not assign?  This is why the capture
                      # stuff should maybe have a separate processing profile (except that having two of every processing profile
                      # would suck, too).
                      #
                      # For now, don't assign to such models.  Worst case, we'll create a new model later on.  
                      my @existing_instrument_data_assignments = Genome::Model::InstrumentDataAssignment->get(model_id => $model->id);
                    
                    EIDA: foreach my $eida (@existing_instrument_data_assignments) {
                          
                          my $eid = Genome::InstrumentData::Solexa->get(id => $eida->instrument_data_id());
			  unless ($eid) {
				$self->warning_message(sprintf("This model has instrument data assigned to it, but the assigned instrument data could not be located (model name %s instrument data id %s)", $model->name, $eida->instrument_data_id));
				next EIDA;
			  }
                          
                          my $eid_capture_target = $eid->target_region_set_name();
                          
                          # Somebody might have manually created a model with capture instrument data with different capture targets.
                          # That's fine, as long as one of the already assigned targets matches the target for the instrument data
                          # we're trying to assign.
                          #
                          # Somebody also might have manually created a model and intentionally assigned capture and non-capture data
                          # to it.
                          # That's fine, as long as one of the already assigned targets matches the target for the insturment data
                          # we're trying to assign, we'll add more (since if we're here, the auto_assign_inst_data flag is set).
                          if (defined($capture_target)) {
                              
                              if (defined($eid_capture_target) && ($eid_capture_target eq $capture_target)) {
                                  $model_is_compatible = 1;
                                  last EIDA;
                              }
                          }
                          else {
                              # No way we're adding non-capture data to a model with capture data already assigned, though.  If somebody
                              # wants that, they'll have to manually assign the non-capture data.
                              if (defined($eid_capture_target)) {
                                  $model_is_compatible = 0;
                                  last EIDA;
                              }
                              else {
                                  $model_is_compatible = 1;
                              }
                              
                          }
                          
                      }
                      
                      if ($model_is_compatible) { 
                          push @compatible_models, $model;
                      }
                      
                  }
                  
                  @models = @compatible_models;
                  
              }
              
              # No existing model that wants this instrument data? Create one!
              unless (@models > 0) {
                  
                  my $model_name = $subject_name .'.'. $pp->name;
                  
                  # Label Solexa capture stuff as such
                  if ($instrument_data_type =~ /solexa/i) {
                      
                      my $capture_target = $genome_instrument_data->target_region_set_name();
                      
                      if (defined($capture_target)) {
                          $model_name = join('.', $model_name, 'capture', $capture_target); 
                      }
                      
                  }
                  
                  my $model = Genome::Model->create(
                      name                  => $model_name,
                      subject_name          => $subject_name,
                      subject_type          => $subject_type,
                      processing_profile    => $pp,
                      auto_assign_inst_data => 1,
                  );
                  
                  unless (defined($model)) {
                      $self->error_message("Failed to create model '$model_name'");
                      push @process_errors, $self->error_message;
                      next PP;
                  }
                  
                  push @models, $model;
                  
              }
              
              foreach my $model (@models) {
                  
                  my @existing_instrument_data = Genome::Model::InstrumentDataAssignment->get(
                      instrument_data_id => $instrument_data_id,
                      model_id => $model->id,
                  );
                  
                  if (@existing_instrument_data) {
                      $self->status_message('Existing instrument_data found for model '. $model->id .' and instrument_data_id '. $instrument_data_id);
                      next;
                  }
                  
                  unless ($model->isa('Genome::Model::PolyphredPolyscan') || $model->isa('Genome::Model::CombineVariants')){
                      
                      my $assign = Genome::Model::Command::InstrumentData::Assign->create(
                          instrument_data_id => $instrument_data_id,
                          model_id => $model->id,
                      );
                      
                      unless ($assign->execute) {
                          $self->error_message('Failed to execute instrument-data assign for model '. $model->id .' and instrument data '. $instrument_data_id);
                          push @process_errors, $self->error_message;
                          next PP;
                      }
                      
                  }
                  
                  # Add model to list of models to build
                  if ($auto_build) {
                      
                      my $model_id = $model->id();
                      my $build_id = $model->current_running_build_id();

                      if ($build_id) {
                          warn "Model '$model_id' is already building ($build_id)"; 
                      }
                      
                      $model_ids{$model->id} = 1;
                    
                  }
                  
              }
              
          }
          
          unless (@process_errors > 0) {
            # Set the pse as completed since this is the end of the line for the pses
            $pse->pse_status("completed");
          } else {
            $self->error_message("Leaving queue instrument data PSE inprogress, due to errors. \n" . join "\n", @process_errors);
          }
          
      }
   
    UR::Context->commit();
    
    #Execute all the builds for models with new data
  MODEL: foreach my $model_id (keys %model_ids) {
       
        
        my $build = Genome::Model::Command::Build->create(
            model_id        => $model_id,
            force_new_build => 1,
        );
        
        unless (defined($build)) { 
            warn "failed to create a Genome::Model::Command::Build for model '$model_id'";
            next MODEL;
        }
        
        eval {
            
            unless ($build->execute) {
                die 'Failed to execute build '. $build->id .' for model '. $model_id;
            }
            
        };
        
        if ($@) {
            warn $@;
            next MODEL;
        }
        
    }

    return 1;
    
}


1;

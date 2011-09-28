package Genome::InstrumentData::Command::Import::HmpSra;

use strict;
use warnings;
use Genome;
use Cwd;
use IO::File;
use File::Path;

class Genome::InstrumentData::Command::Import::HmpSra {
    is  => 'Command',
    has_input => [
        run_id => {
            is_optional => 1,
            doc => 'A single SRR ID',
        },
	run_ids => { 
	    is_optional => 1, 
            doc => 'a file of SRR ids',
	},
        tmp_dir => {
            is_optional => 1,
            doc => 'override the temp dir used during processing (no auto cleanup)',
        },
        container_dir => {
            is_optional => 1,
            doc => 'location where SRA data objects already exist if you wish to shortcut downloading',
        },
    ],
    doc => 'download an import short read archive HMP data',
};

sub execute {
    my $self = shift;

    my $scripts_dir = $self->get_script_path;
    $self->status_message("Scripts are in: $scripts_dir");    
    unless ($scripts_dir) {
        $self->error_message("Failed to resolve scripts dir");
        return;
    }
    #### jmartin 100813
    ####my @srr_ids = $self->run_ids;
    my @srr_ids;

    if ($self->run_ids) {
        my $fh = new IO::File $self->run_ids;

        while (<$fh>) {
            chomp;
            my $line = $_;
            next if ($line =~ /^\s*$/);
            push(@srr_ids,$line);
        }
        $fh->close;
    } elsif ($self->run_id) {
        push @srr_ids, $self->run_id;
    } else {
        $self->error_message("You must specify a run id or a list of run ids in a file");
        return;
    }
    

    # validate
    for my $id (@srr_ids) {
        my $sample = Genome::Sample->get(sql=>qq/
            select os.*
            from gsc.organism_sample os 
            join gsc.sra_organism_sample sos on sos.organism_sample_id=os.organism_sample_id
            join gsc.sra_experiment ex on ex.sra_sample_id=sos.sra_sample_id
            join gsc.sra_run ru on ru.sra_experiment_id=ex.sra_item_id 
            join gsc.sra_item rui on rui.sra_item_id=ru.sra_item_id 
            join gsc.sra_accession ruacc on ruacc.alias=rui.alias  
            where ruacc.accession='$id'
        /);
        unless ($sample) {
            $self->error_message("Failed to get a sample object from the warehouse for SRR ID $id.");
            return;
        }
    }

    $self->status_message("SRR ids are: @srr_ids");

    my $tmp = $self->tmp_dir;
    if ($tmp) {
        unless (-d $tmp) {
            $self->error_message("temp directory $tmp not found!");
            return;
        }
        $self->status_message("Override temp dir is $tmp");
    }
    else {
        $tmp = Genome::Sys->create_temp_directory();
        $self->status_message("Autogenerateed temp data is in $tmp");
    }

    my $junk_tmp = $tmp . '/junk';
    Genome::Sys->create_directory($junk_tmp);

    my $errfile;
    my $cmd;

    # build the SRA index
    my $sra_index_file = $tmp . '/SRA-index.txt';

    # download each
    # TODO: it may be better to do in bulk, or better individually for max speed per item

    for my $srr_id (@srr_ids) {
        # did we already import this one?
        
        if (Genome::InstrumentData::Imported->get(sra_accession=>$srr_id, import_format=>'raw sra download')) {
            $self->status_message("$srr_id already exists in the system as a raw sra download.  Skipping!");
            next;
        }

        # can we skip downloading this one?
        if (-d $self->container_dir . "/" . $srr_id) {
            unless($self->slurp_srr_data(id=>$srr_id,
                                  directory => $self->container_dir . "/" . $srr_id)) {
                $self->error_message("Failed slurping SRR data");
                return; 
            }
            next;
        } 
  
        # check if we need to build the index 
        unless (-e $sra_index_file) {  
            $errfile = $sra_index_file . '.err';
            $cmd = "cd $junk_tmp; $scripts_dir/build_public_SRA_run_index.pl --reuse_files "
                . ' > ' . $sra_index_file 
                . ' 2> ' . $errfile;        
            Genome::Sys->shellcmd(
                cmd => $cmd,
                output_files => [$sra_index_file,$errfile],
                skip_if_output_is_present => 1,
            );
        }

        # download each

        my $fof = "$tmp/$srr_id.fof";
        Genome::Sys->write_file($fof, $srr_id);
        
        my $log = $fof;
        $log =~ s/.fof/.log/;

	#### jmartin ... 100813
        ####my $results_dir = "$tmp/$srr_id";
	my $results_dir = "$tmp/$srr_id";

        if (-d $results_dir) {
            $self->status_message("Found directory, skipping download: $results_dir");
        }
        else {
	    my $out = $fof . '.download.out';
	    my $err = $fof . '.download.err';


	    #### jmartin ... 100813
            ####my $cmd = "cd $tmp; $scripts_dir/get_SRA_runs.pl ascp $sra_index_file $fof >$out 2>$err";
	    my $cmd = "cd $tmp; $scripts_dir/get_SRA_runs.pl ascp $sra_index_file $fof >$out 2>$err";

            Genome::Sys->shellcmd(
                cmd => $cmd,
                input_files => [$fof],
		output_files => [$out],
                output_directories => [$results_dir],
                skip_if_output_is_present => 1,
            );

	    my $out_content = Genome::Sys->read_file($out);
	    ####if ($out_content =~ /transferred .* SRA runs with ascp, (\d+) failures(s) detected/) {
	    if ($out_content =~ /transferred\s+.*\s+SRA\s+runs\s+with\s+ascp\,\s+(\d+)\s+failure\(s\)\s+detected/) {
		my $failures = $1;
		if ($failures == 0) {
		    $self->status_message("No failures from the download");
                            unless($self->slurp_srr_data(id=>$srr_id,
                                               directory => $tmp . "/" . $srr_id)) {
                $self->error_message("Failed slurping SRR data");
                return; 
            }
                    $self->status_message("Removing synced SRA download from tmp");
                    rmtree($tmp . "/" . $srr_id);
		}
		else {
		    $self->error_message("$failures failures downloading!  STDOUT is:\n$out_content\n");
                    return;
		}
	    }
	    else {
		$self->error_message("No completion line in the log file.  Content is: $out_content");
                return;
	    }
        }
    }

    return 1;
}

sub slurp_srr_data {
    my $self = shift;
    my %p = @_;

    my $srr_id = $p{id};
    my $path = $p{directory};

    if (-l $path) {
        $self->status_message("$path is really a symlink.  Following it!");
        $path = readlink($path);
        unless ($path)  {
            $self->error_message("Cannot follow symlink!");
            return;
        }
        $self->status_message("Resolved link to $path");
    }
    
    $self->status_message("Slurping $srr_id from path $path");
    
    my $original_md5_contents = `cat $path/col/READ/md5 | grep data`;
    my ($expected_md5) = split /\s+/, $original_md5_contents;
    my $new_md5 = Genome::Sys->md5sum("$path/col/READ/data");

    $self->status_message("Expected $expected_md5, got $new_md5");

    unless ($expected_md5 eq $new_md5) {
        $self->error_message("MD5 hash mismatch, $path failed integrity check: expected $expected_md5, got $new_md5");
        return;
    }

    my %params = ();

    my $dbh = Genome::DataSource::GMSchema->get_default_handle();
    my ($fc_id, $lane) = $dbh->selectrow_array(qq/select ii.flow_cell_id, ii.lane
    from gsc.organism_sample os 
    join gsc.sra_organism_sample sos on sos.organism_sample_id=os.organism_sample_id
    join gsc.sra_experiment ex on ex.sra_sample_id=sos.sra_sample_id
    join gsc.sra_run ru on ru.sra_experiment_id=ex.sra_item_id 
    join gsc.sra_item rui on rui.sra_item_id=ru.sra_item_id 
    join gsc.sra_accession ruacc on ruacc.alias=rui.alias
    join gsc.index_illumina ii on ii.seq_id=rui.source_entity_id and rui.source_entity_type='index illumina' 
    where ruacc.accession='$srr_id'/);

    unless (defined $fc_id && defined $lane) {
        $self->error_message("Couldn't recover original flow cell id and lane for this SRR id $srr_id");
        return;
    }

    my $original_inst = Genome::InstrumentData::Solexa->get(flow_cell_id=>$fc_id, lane=>$lane);

    unless ($original_inst) {
        $self->error_message("Couldn't recover original instrument data for this SRR id $srr_id");
        return;
    }

    $params{library_id} = $original_inst->library_id;
    $params{sample_id} = $original_inst->sample_id;
    $params{sample_name} = $original_inst->sample_name;
    $params{original_data_path} = $path;
    $params{sequencing_platform} = 'solexa';
    $params{import_format} = 'raw sra download';
    $params{sra_accession} = $srr_id;

    my $import_instrument_data = Genome::InstrumentData::Imported->create(%params);  
    unless ($import_instrument_data) {
       $self->error_message('Failed to create imported instrument data for '.$self->original_data_path);
       return;
    }

    my $alloc_path = sprintf('instrument_data/imported_raw_sra/%s', $import_instrument_data->id);
    my $kb_used = $self->disk_usage_for_srr_path($path);
    unless ($kb_used) {
        $self->error_message("Can't resolve kb usage");
        return;
    }

    my %alloc_params = (
        disk_group_name     => 'info_alignments',     #'info_apipe',
        allocation_path     => $alloc_path,
        kilobytes_requested => $kb_used,
        owner_class_name    => $import_instrument_data->class,
        owner_id            => $import_instrument_data->id,
    );


    my $disk_alloc = Genome::Disk::Allocation->allocate(%alloc_params);
    unless ($disk_alloc) {
        $self->error_message("Failed to get disk allocation with params:\n". Data::Dumper::Dumper(%alloc_params));
        return;
    }

    $self->status_message("Now de-staging data from $path into " .$disk_alloc->absolute_path); 
    my $call = sprintf("rsync -rptgovz --copy-links %s %s", $path, $disk_alloc->absolute_path);

    my $rv = system($call);
    $self->status_message("Running Rsync: $call");

    unless ($rv == 0) {
        $self->error_message("Did not get a valid return from rsync, rv was $rv for call $call.  Cleaning up and bailing out");
        $disk_alloc->deallocate;
        return;
    }

    return 1;
}

sub disk_usage_for_srr_path { 
    my $self = shift;
    my $path = shift;

    my $cmd = "du -sk $path 2>&1";
    my $du_output = qx{$cmd};
    my $kb_used = ( split( ' ', $du_output, 2 ) )[0];
    Scalar::Util::looks_like_number($kb_used)
        or return;
    $self->status_message("Successfully got disk usage ($kb_used KB) for $path");

    return $kb_used;
}

sub get_script_path {
    my $self = shift;
    my $file   = __PACKAGE__;
    $file =~ s{::}{/}g;
    $file .= ".pm";

    my $path;
    for my $dir (@INC) {
        $path = $dir . "/" . $file;
        last if -r $path;
        $path = undef;
    }
    
    $path =~ s/\.pm$//;

    return $path;
}


1;


package Genome::Model::Command::Build::ReferenceAlignment::DeduplicateLibraries::DedupSam;

use strict;
use warnings;

use Genome;

use File::Basename;
use IO::File;

class Genome::Model::Command::Build::ReferenceAlignment::DeduplicateLibraries::DedupSam {
    is => ['Command'],
    has_input => [
    accumulated_alignments_dir => {
        is => 'String',
        doc => 'Accumulated alignments directory.' 
    },
    library_alignments => {
        is => 'String',
        doc => 'Hash of library names and related alignment files.' 
    },
    rmdup_version => {
                        is => 'Text',
                        doc => 'The version of rmdup tools (samtools) used',
                    },
    ],
    has_param => [
        lsf_resource => {
            default_value => 'select[model!=Opteron250 && type==LINUX64] rusage[mem=2000]',
        }
    ],


    has_output => [
    output_file => { 
        is => 'String', 
        is_optional => 1, 
    },
    library_name => { 
        is => 'String', 
        is_optional => 1, 
    }
    ],
};

sub execute {
    my $self=shift;

    my $pid = getppid(); 
    my $log_dir = $self->accumulated_alignments_dir.'/../logs/';
    unless (-e $log_dir ) {
	unless( Genome::Utility::FileSystem->create_directory($log_dir) ) {
            $self->error_message("Failed to create log directory for dedup process: $log_dir");
            return;
	}
    }
 
    my $log_file = $log_dir.'/parallel_sam_rmdup_'.$pid.'.log';
    my $log_fh = Genome::Utility::FileSystem->open_file_for_writing($log_file);
    unless($log_fh) {
       $self->error_message("Failed to open output filehandle for: " .  $log_file );
       die "Could not open file ".$log_file." for writing.";
    } 

    my $now = UR::Time->now;
    print $log_fh "Executing DedupSam.pm at $now"."\n";

       
 
    my @list;
    if ( ref($self->library_alignments) ne 'ARRAY' ) {
        push @list, $self->library_alignments; 		
    } else {
        @list = @{$self->library_alignments};   	#the parallelized code will only receive a list of one item. 
    }

    print $log_fh "Input library list length: ".scalar(@list)."\n";
    for my $list_item ( @list  ) {
        my %hash = %{$list_item };    		#there will only be one name-value-pair in the hash: $library name -> @list of alignment file paths (maps)
        for my $library ( keys %hash ) {
            $self->library_name($library);
            my @library_maps = @{$hash{$library}};
            print $log_fh "key:>$library<  /  value:>".scalar(@library_maps)."<"."\n";

            $now = UR::Time->now;
            print $log_fh ">>> Starting bam merge at $now for library: $library ."."\n";
            print $log_fh "Merging maps:\n";
            print $log_fh join("\n",@library_maps);
            print $log_fh "\n";
            
            my $merged_file =  $self->accumulated_alignments_dir."/".$library.".bam";
            if (-e $merged_file) {
                print $log_fh "A merged library file already exists at: $merged_file \n";
                print $log_fh "Please remove this file if you wish to regenerate. Skipping to rmdup phase.\n";
                $now = UR::Time->now;
                print $log_fh "<<< Skipped bam merge at $now for library: $library ."."\n";
            } else {
                my $merge_rv = Genome::Model::Tools::Sam::Merge->execute(files_to_merge=>\@library_maps,merged_file=>$merged_file,is_sorted=>1); 

                unless ($merge_rv) {
                    print $log_fh "There was a problem merging ".join(",",@library_maps). " to $merged_file.";
                    $log_fh->close;
                    return; 
                }
                
                $now = UR::Time->now;
                print $log_fh "<<< Completed bam merge at $now for library: $library ."."\n";
                
            } 
            
            print $log_fh ">>> Starting rmdup at $now  for library: $library ."."\n";
     
            #bail if the final file already exists
            my $rmdup_file =  $self->accumulated_alignments_dir."/".$library."_merged_rmdup.bam";
            if (-e $rmdup_file) {
               print $log_fh "An rmdup'd library file already exists at: $rmdup_file \n";
               print $log_fh "Please remove this file if you wish to regenerate. Quitting. \n";
               $now = UR::Time->now;
               print $log_fh "<<< Skipped rmdup at $now  for library: $library ."."\n";
               $log_fh->close;
               return 1;  
            }
      
            #my $rmdup_file =  $self->accumulated_alignments_dir."/".$library."_merged_rmdup.bam";
            #my $rmdup_tool = "/gscuser/dlarson/src/samtools/tags/samtools-0.1.2/samtools rmdup";
            my $rmdup_tool = Genome::Model::Tools::Sam->path_for_samtools_version($self->rmdup_version);
            $rmdup_tool .= ' rmdup';
            my $report_file = $log_dir."/".$pid."_".$library."_rmdup.out";
            my $rmdup_cmd = $rmdup_tool." ".$merged_file." ".$rmdup_file." >& $report_file";
            print $log_fh "Rmduping with cmd: $rmdup_cmd";
            my $rmdup_rv = Genome::Utility::FileSystem->shellcmd( cmd=>$rmdup_cmd );

            unless ($rmdup_rv) {
                print $log_fh "There was a problem rmduping!  Command return value: $rmdup_rv";
                $log_fh->close;
                return; 
            }

            $now = UR::Time->now;
            print $log_fh "<<< Completed rmdup at $now  for library: $library ."."\n";

	}#end library loop 

    print $log_fh "*** Dedup process completed ***";
    }#end parallelized item loop

   $log_fh->close;
   return 1;
} #end execute




1;

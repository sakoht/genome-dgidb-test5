
package Genome::Model::Tools::AssembleReads::Pcap::CreateDirectories;

use strict;
use warnings;

use lib '/gscuser/kkyung/svn/pm';

use Workflow;
use above "Genome";
use Genome::Model::Tools::AssembleReads::Pcap;

class Genome::Model::Tools::AssembleReads::Pcap::CreateDirectories
{
    is => 'Command',
    has => [
	    disk_location => { type => 'String', doc => 'path to assembly'},
	    project_name => { type => 'String', doc => 'project or organism name'},
	    assembly_version => { type => 'String', doc => 'assembly version num'},
	    assembly_date => { type => 'String', doc => 'assembly date'},
           ],
};

operation Genome::Model::Tools::AssembleReads::Pcap::CreateDirectories {
    input  => [ 'disk_location', 'project_name', 'assembly_version', 'assembly_date' ],
    output => [  ],
};
        

sub execute
{
    my $self = shift;

    my $disk = $self->disk_location;
    my $proj_name = $self->project_name;
    my $asm_ver = $self->assembly_version;
    my $date = $self->assembly_date;

    my $path = $disk.'/'.$proj_name.'-'.$asm_ver.'_'.$date.'.pcap';

    mkdir "$path" unless -d $path;

    $self->error_message ("Failed to create $path") and return unless -d $path;

    foreach my $sub_dir (qw/ edit_dir input output phd_dir chromat_dir blastdb acefiles ftp read_dump/)
    {
	next if -d "$path/$sub_dir";

        mkdir "$path/$sub_dir";

        unless (-d "$path/$sub_dir")
        {
            $self->error_message ("failed to create $path/$sub_dir : $!");
            return;
        }
    }

    return 1;
}

1;

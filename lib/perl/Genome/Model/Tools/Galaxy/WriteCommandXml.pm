
package Genome::Model::Tools::Galaxy::WriteCommandXml;

use strict;
use warnings;
use Genome;

class Genome::Model::Tools::Galaxy::WriteCommandXml {
    is  => 'Command',
    has => [
        command => {
            is  => 'String',
            doc => 'command to search for command subclasses of',
            default => 'Genome'
        },
        galaxy_dir => {
            is => 'String',
            doc => 'Galaxy directory to find tool_conf.xml and tools directory Example: ~/hg/galaxy-central/'
        }
    ]
};

sub execute {
    my $self = shift;

    my $command = $self->command;
    my $outdir = $self->galaxy_dir;

    my @written_xml = ();

    if (!-e "$outdir/tool_conf.xml" || !-e "$outdir/tools") {
        $self->error_message("No tool_conf.xml or tools in this directory");
        return 0;
    }

    if (!-e "$outdir/tools/genome") {
        mkdir "$outdir/tools/genome";
    }

    foreach my $c ($command->sorted_sub_command_classes) {
        my $gen = Genome::Model::Tools::Galaxy::GenerateToolXml->create(
            class_name => $c,
            'print' => 0
        );
        $gen->execute;
    
        my $munged_name = $c->command_name;
        $munged_name =~ s/ /_/g;
        print "Writing: $outdir/tools/genome/$munged_name.xml\n";

        open my $fh, ">$outdir/tools/genome/$munged_name.xml" or last;
        print $fh $gen->output;
        close $fh;
        push @written_xml, "genome/$munged_name.xml";
    }

    my $new_genome_section = '  <section name="Genome" id="genome">' . "\n";
    foreach my $wr (@written_xml) {
        $new_genome_section .= '    <tool file="' . $wr . '"/>' . "\n";
    }
    $new_genome_section .= '  </section>' . "\n";

    local $/;
    open my $fh, "<$outdir/tool_conf.xml";
    my $tool_xml = <$fh>;
    close $fh;

    unless($tool_xml =~ s/^\s+<section name="Genome" id="genome">.*?<\/section>\n/$new_genome_section/ms) {
        $tool_xml =~ s/^<toolbox>\n/<toolbox>\n$new_genome_section/ms;
    }

    open my $ofh, ">$outdir/tool_conf.xml";
    print $ofh $tool_xml;
    close $ofh;
}

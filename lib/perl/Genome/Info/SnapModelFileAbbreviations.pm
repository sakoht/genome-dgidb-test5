package Genome::Info::SnapModelFileAbbreviations;

use strict;
use warnings;

my %model_files = (
    'A.canium.hmm' => 'sn_acan',
    'B.malayi.hmm' => 'sn_bmal',
    'bmal.intronset.hmm' => 'sn_bmal30',
    'C.elegans.hmm' => 'sn_cele',
    'caninum_cegma.hmm' => 'sn_accg',
    'caninum_maker.hmm' => 'sn_acmk',
    'spiralis_cegma_mod.hmm' => 'sn_tscg',
    'spiralis_cegma_mod_intron_min30.hmm' => 'sn_tscg30',
    'D.viviparus_cegma.hmm' => 'sn_dvcg',
    'N.americanus_cegma.hmm' => 'sn_nacg',
	'S_cerevisiae_ref_cegma.hmm' => 'sn_screfcg',
	'Namericanus.4.2.1.cegma.hmm' => 'sn_nacg421',
	'Acaninum.9.3.2.cegma.hmm ' => 'sn_accg932',
	'Namericanus_4.2.2.ec.cg.v4.hmm' => 'sn_nacg422ecv4',
	'Namericanus_4.2.2.ec.mkrd.v3.hmm' => 'sn_namkrd422ecv3',
	'Namericanus_4.2.2.ec.mkis.v3.hmm' => 'sn_namkis422ecv3',
	'Namericanus_4.2.2.ec.mkcb.v3.hmm' => 'sn_namkcb422ecv3',
);

sub abbreviation_for_model_file {
    my $model_file = shift;
    return $model_files{$model_file};
}

1;


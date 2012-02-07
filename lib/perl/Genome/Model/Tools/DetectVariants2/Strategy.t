#!/usr/bin/env perl

use strict;
use warnings;

use Parse::RecDescent qw/RD_ERRORS RD_WARN RD_TRACE/;
use Data::Dumper;
use Test::More tests => 23;
use above 'Genome';

#Parsing tests
my $gmt_dv2 = 'Genome::Model::Tools::DetectVariants2';
my $strategy_class = "${gmt_dv2}::Strategy";
use_ok($strategy_class);

# hash of strings => expected output hash
my %expected = (
    "samtools v1" => {
        detector => {
            name => "samtools",
            class => "${gmt_dv2}::Samtools",
            version => "v1",
            params => '',
            filters => [],
        }
    },

    "varscan v2 [--foo] intersect samtools v1 [-p1] filtered by thing v1" => {
        intersect => [
            {
                detector => {
                    name => "varscan",
                    class => "${gmt_dv2}::Varscan",
                    version => "v2",
                    params => '--foo',
                    filters => [],
                },
            },
            {
                detector => {
                    name => "samtools",
                    class => "${gmt_dv2}::Samtools",
                    version => "v1",
                    params => '-p1',
                    filters => [
                        {
                            name => 'thing',
                            version => 'v1',
                            params => '',
                            class => "${gmt_dv2}::Filter::Thing"
                        }
                    ],
                }
            },
        ]
    },

    "a v1 [-b 1] filtered by c v2 then d v3 [-f] union (a v1 intersect b v2)" => {
        union => [
            {
                detector => {
                    name => "a",
                    class => "${gmt_dv2}::A",
                    version => "v1",
                    params => '-b 1',
                    filters => [
                        {name => 'c', version => 'v2', params => '', class => "${gmt_dv2}::Filter::C"},
                        {name => 'd', version => 'v3', params => '-f', class => "${gmt_dv2}::Filter::D"},
                     ],
                },
            },
            {
                intersect => [
                    {
                        detector => {
                            name => "a",
                            class => "${gmt_dv2}::A",
                            version => "v1",
                            params => '',
                            filters => [],
                        },
                    },
                    {
                        detector => {
                            name => "b",
                            class => "${gmt_dv2}::B",
                            version => "v2",
                            params => '',
                            filters => [],
                        },
                    },
                ],
            },
        ],
    }
);

my @expected_failures = (
    "badness", # missing version, params
    "badness v1 filtered by", # missing filter
    "badness v1 filtered by foo", # missing filter version
    "badness v1 filtered by foo v1", # missing filter params
    "badness v1 filtered by foo v1 [] intersect", # missing detector after 'intersect'
    "(badness v1 filtered by foo v1 []", # missing )
    "badness v1 filtered by foo v1)", # extra )
);
    
is("${gmt_dv2}::Samtools", $strategy_class->detector_class("samtools"), "names without subpackages parsed correctly");
is("${gmt_dv2}::Somatic::Varscan", $strategy_class->detector_class("somatic varscan"), "names with subpackages parsed correctly");

for my $str (keys %expected) {
    my $obj = $strategy_class->get($str);
    my $tree = $obj->tree;
    ok($tree, "able to parse detector string $str")
        or die "failed to parse $str";
    is_deeply($tree, $expected{$str}, "tree looks as expected for $str") 
        or die "incorectly parsed $str: expected: " . Dumper($expected{$str}) . "got: " . Dumper($tree);
}

# don't want to see all the yelling while testing failures.
$::RD_ERRORS = undef;
$::RD_WARN = undef;
$::RD_TRACE = undef;
for my $str (@expected_failures) {
    my $tree = undef;
    my $obj = $strategy_class->get($str);
    eval {
        my $tree = $obj->tree;
    };
    ok(!$tree, 'bad input fails to parse as expected')
        or die "did not fail to parse bad string: $str";
    eval {
        my @errs = $obj->__errors__;
        ok($obj->__errors__, 'object has errors as expected');
    };
}


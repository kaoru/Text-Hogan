#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '/home/alex/Documents/Git/Hogan.pm/lib';

use Hogan::Compiler;
use Hogan::Template;

my $c = Hogan::Compiler->new();

my $text = "{{#list-one}}x{{.}}{{#list-two}}y{{.}}{{/list-two}}\n{{/list-one}}";

my $s = $c->scan($text);

my $p = $c->parse($s, $text);

my $g = $c->generate($p, $text, {});

say $c->generate($p, $text, { as_string => 1 }), "\n\n";

my $o = $g->render({ 'list-one' => [ 1, 2, 3 ], 'list-two' => [ qw(a b c) ] });

say $o;

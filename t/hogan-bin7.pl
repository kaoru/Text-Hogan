#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '/home/alex/Documents/Git/Hogan.pm/lib';

use Hogan::Compiler;
use Hogan::Template;

my $c = Hogan::Compiler->new();

my $text = "{{#list}}({{.}}){{/list}}";

my $s = $c->scan($text);

my $p = $c->parse($s, $text);

my $g = $c->generate($p, $text, {});

say $c->generate($p, $text, { as_string => 1 }), "\n\n";

my $o = $g->render({ list => [ qw(1.10 2.20 3.30 4.40 5.50) ] });

say $o;

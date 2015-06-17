#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '/home/alex/Documents/Git/Hogan.pm/lib';

use Hogan::Compiler;
use Hogan::Template;

my $c = Hogan::Compiler->new();

my $text = "{{#contexts}} {{#are}} {{fun}} {{/are}} {{/contexts}}\n{{#contexts}} {{^not}} {{dots.deeper.foo}} {{/not}} {{/contexts}}\n";

my $s = $c->scan($text);

my $p = $c->parse($s, $text);

my $g = $c->generate($p, $text, {});

say $c->generate($p, $text, { as_string => 1 }), "\n\n";

my $o = $g->render({ contexts => { are => 1, fun => "YAY", not => 0, dots => { "deeper" => { "foo" => "WOAH" } } } });

say $o;

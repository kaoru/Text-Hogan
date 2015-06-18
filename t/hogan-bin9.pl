#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '/home/alex/Documents/Git/Hogan.pm/lib';

use Hogan::Compiler;
use Hogan::Template;

my $c = Hogan::Compiler->new();

my $text = '{{=<% %>=}}(<%text%>)';

my $s = $c->scan($text);

use DDP; p $s;

my $p = $c->parse($s, $text);

my $g = $c->generate($p, $text, {});

say $c->generate($p, $text, { as_string => 1 }), "\n\n";

my $o = $g->render({ text => "Hey!" });

say $o;

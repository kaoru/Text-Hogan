#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '/home/alex/Documents/Git/Hogan.pm/lib';

use Hogan::Compiler;
use Hogan::Template;

my $c = Hogan::Compiler->new();

my $text = "Hello, {{name}}!";

my $s = $c->scan($text);

my $p = $c->parse($s, $text);

my $g = $c->generate($p, $text, {});

my $o = $g->render({ name => "Alex" });

say $o;

#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use Text::Hogan::Compiler;

my $compiler = Text::Hogan::Compiler->new;

my $text = "Hello, {{name}}!";

my $tokens   = $compiler->scan($text);
my $tree     = $compiler->parse($tokens, $text);
my $template = $compiler->generate($tree, $text);

is $template->render({ name => "Alex" }), "Hello, Alex!", "Text::Hogan::Compiler synopsis works";


done_testing();

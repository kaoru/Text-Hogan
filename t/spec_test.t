#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use YAML;
use Path::Tiny;
use Try::Tiny;
use Data::Visitor::Callback;

use Text::Hogan::Compiler;

my $data_fixer = Data::Visitor::Callback->new(
    # Handle true/false values
    hash => sub {
        my ($self, $rh) = @_;
        for my $v (values %$rh) {
            if ($v eq 'true') { $v = 1 }
            elsif ($v eq 'false') { $v = 0 }
            elsif (ref($v) eq 'HASH') { $self->visit($v) }
        }
    }
);

my @spec_files = path("t", "specs")->children(qr/[.]yml$/);

for my $file (sort @spec_files) {
    my $yaml = $file->slurp_utf8;

    my $specs = YAML::Load($yaml);

    note "----- $file ", ("-" x (70-length($file)));

    for my $test (@{ $specs->{tests} }) {
        #
        # Handle true/false values
        #
        $data_fixer->visit($test->{data});

        #
        # Handle lambdas in the ~lambdas.yml spec file
        #
        {
            for my $key (keys %{ $test->{data} }) {
                if (ref $test->{data}{$key} eq 'HASH' && exists $test->{data}{$key}{perl}) {
                    $test->{data}{$key} = eval $test->{data}{$key}{perl};
                }
            }
        }

        my $parser = Text::Hogan::Compiler->new();

        my $rendered;
        try {
            $rendered = $parser->compile($test->{template})->render($test->{data}, $test->{partials});
        };
        is(
            $rendered,
            $test->{expected},
            "$test->{name} - $test->{desc}"
        );
    }
}

done_testing();

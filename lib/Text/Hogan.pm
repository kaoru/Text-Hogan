package Text::Hogan;

use strict;
use warnings;

1;

__END__

=head1 NAME

Text::Hogan - A mustache templating engine statement-for-statement cloned from hogan.js

=head1 SYNOPSIS

    use Text::Hogan::Compiler;

    my $text = "Hello, {{name}}!";

    my $compiler = Text::Hogan::Compiler->new;
    my $template = $compiler->compile($text);

    say $template->render({ name => "Alex" });

See L<Text::Hogan::Compiler|Text::Hogan::Compiler> and L<Text::Hogan::Template|Text::Hogan::Template> for more details.

=head1 SEE ALSO

=head2 Text::Caml

L<Text::Caml|Text::Caml> is a very good mustache-like templating engine, but
does not support pre-compilation.

=head2 Template::Mustache

L<Template::Mustache|Template::Mustache> is a module written by Pieter van de
Bruggen and Ricardo Signes. Currently has no POD. Used by
Dancer::Template::Mustache.

=head1 COPYRIGHT

Copyright (C) 2015 Lokku Ltd.

=head1 AUTHOR

Statement-for-statement copied from hogan.js by Twitter!

Alex Balhatchet (alex@lokku.com)

=cut

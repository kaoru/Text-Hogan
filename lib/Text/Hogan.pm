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

See Text::Hogan::Compiler and Text::Hogan::Template for more details.

=head1 COPYRIGHT

Copyright (C) 2015 Lokku Ltd.

=head1 AUTHOR

Statement-for-statement copied from hogan.js by Twitter!

Alex Balhatchet (alex@lokku.com)

=cut
